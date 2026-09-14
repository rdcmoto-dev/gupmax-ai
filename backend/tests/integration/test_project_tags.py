from uuid import uuid4

import pytest
from sqlalchemy import select

from app.db.base import Base
from app.modules.ai_gateway.service import AIGatewayService
from app.modules.projects import service

ROOT = '/api/v1/project-tags'


def auth(client, email='tags@example.com'):
    response = client.post('/api/v1/auth/register', json={
        'email': email, 'full_name': 'Tags User', 'password': 'SecurePassword123!',
    })
    assert response.status_code == 201
    return {'Authorization': f"Bearer {response.json()['access_token']}"}


def project(client, owner):
    response = client.post('/api/v1/projects', headers=owner, json={
        'name': 'Projeto Tags', 'context': 'Objetivo: Entregar\nMarco: [x] Pronto\nProjeto encerrado: sim',
    })
    assert response.status_code == 201
    return response.json()


def tag(client, owner, name='Trabalho'):
    response = client.post(ROOT, headers=owner, json={'name': name})
    assert response.status_code == 201, response.text
    return response.json()


async def snapshot(factory):
    async with factory() as session:
        return {table.name: [dict(row) for row in (
            await session.execute(select(table).order_by(*table.primary_key.columns))
        ).mappings()] for table in Base.metadata.sorted_tables}


def test_existing_project_association_reaches_list_with_catalog_id(client):
    owner = auth(client)
    associated = project(client, owner)
    unassociated = project(client, owner)
    marketing = tag(client, owner, 'Marketing')
    instagram = tag(client, owner, 'Instagram')
    link = f"{ROOT}/projects/{associated['id']}/{marketing['id']}"
    assert client.put(link, headers=owner).status_code == 204

    # A new request/session must read the committed association, using the
    # catalog UUID (never the label) as the filter key.
    catalog = client.get(ROOT, headers=owner).json()
    tag_id = next(item['id'] for item in catalog if item['id'] == marketing['id'])
    page = client.get('/api/v1/projects?include_archived=true&limit=100', headers=owner).json()
    matched = [item['id'] for item in page['items'] if any(t['id'] == tag_id for t in item['tags'])]
    assert matched == [associated['id']]
    assert unassociated['id'] not in matched
    assert all(t['id'] != instagram['id'] for item in page['items'] for t in item['tags'])
    assert client.get(f"/api/v1/projects/{associated['id']}", headers=owner).json()['tags'] == [marketing]


@pytest.mark.parametrize('names,remove_index', [
    (('Marketing', 'Instagram'), 1),
    (('Marketing', 'Instagram', 'Teste935'), 2),
])
def test_multiple_tags_persist_and_detach_keeps_catalog(client, names, remove_index):
    owner = auth(client)
    response = client.post('/api/v1/projects', headers=owner,
                           json={'name': 'Lançamento Pizzaria Donatello'})
    assert response.status_code == 201
    project_id = response.json()['id']
    other = project(client, owner)
    records = [tag(client, owner, name) for name in names]
    ids = {record['id'] for record in records}
    for record in records:
        assert client.put(f"{ROOT}/projects/{project_id}/{record['id']}", headers=owner).status_code == 204

    def read_and_filter(expected):
        # Every request opens a fresh DB session: no shared in-memory Project.
        detail = client.get(f'/api/v1/projects/{project_id}', headers=owner).json()
        assert {t['id'] for t in detail['tags']} == expected
        page = client.get('/api/v1/projects?include_archived=true&limit=100', headers=owner).json()['items']
        for tag_id in ids:
            found = {p['id'] for p in page if any(t['id'] == tag_id for t in p['tags'])}
            assert found == ({project_id} if tag_id in expected else set())
            assert other['id'] not in found

    read_and_filter(ids)
    read_and_filter(ids)
    removed_id = records[remove_index]['id']
    assert client.delete(f'{ROOT}/projects/{project_id}/{removed_id}', headers=owner).status_code == 204
    read_and_filter(ids - {removed_id})
    assert {t['id'] for t in client.get(ROOT, headers=owner).json()} == ids


def test_crud_persistence_literal_names_and_no_other_writes(client, session_factory, monkeypatch):
    owner = auth(client)
    original = project(client, owner)
    path = f"/api/v1/projects/{original['id']}"

    def forbidden(*args, **kwargs):
        raise AssertionError('Tags must not call AI')

    monkeypatch.setattr(AIGatewayService, 'generate', forbidden)
    monkeypatch.setattr(AIGatewayService, 'stream', forbidden)
    before = client.portal.call(snapshot, session_factory)
    record = tag(client, owner, '  <script>literal</script>  ')
    assert record['name'] == '<script>literal</script>'
    link = f"{ROOT}/projects/{original['id']}/{record['id']}"
    for _ in range(2):
        assert client.put(link, headers=owner).status_code == 204
    detail = client.get(path, headers=owner).json()
    assert detail['tags'] == [record]
    assert {key: detail[key] for key in original} == {**original, 'tags': [record]}
    assert client.get('/api/v1/projects', headers=owner).json()['items'][0]['tags'] == [record]
    renamed = client.put(f"{ROOT}/{record['id']}", headers=owner, json={'name': 'Cliente'}).json()
    assert renamed['id'] == record['id']
    assert client.get(path, headers=owner).json()['tags'] == [renamed]
    after = client.portal.call(snapshot, session_factory)
    for table in before:
        if table not in {'project_tags', 'project_tag_links'}:
            assert after[table] == before[table], table
    for _ in range(2):
        assert client.delete(link, headers=owner).status_code == 204
    assert client.get(path, headers=owner).json()['tags'] == []
    assert client.put(link, headers=owner).status_code == 204
    assert client.delete(f"{ROOT}/{record['id']}", headers=owner).status_code == 204
    assert client.get(path, headers=owner).json()['tags'] == []
    assert client.portal.call(snapshot, session_factory) == before


def test_tags_ownership_all_routes(client):
    owner, stranger = auth(client), auth(client, 'stranger-tags@example.com')
    own_project, foreign_project = project(client, owner), project(client, stranger)
    own_tag, foreign_tag = tag(client, owner), tag(client, stranger)
    assert client.get(ROOT, headers=stranger).json() == [foreign_tag]
    paths = [('GET', ROOT, None), ('POST', ROOT, {'name': 'Name'}),
             ('PUT', f"{ROOT}/{own_tag['id']}", {'name': 'Name'}),
             ('DELETE', f"{ROOT}/{own_tag['id']}", None),
             ('PUT', f"{ROOT}/projects/{own_project['id']}/{own_tag['id']}", None),
             ('DELETE', f"{ROOT}/projects/{own_project['id']}/{own_tag['id']}", None)]
    for method, path, data in paths:
        assert client.request(method, path, json=data).status_code == 401
    for method in ('PUT', 'DELETE'):
        for id in (own_tag['id'], str(uuid4())):
            assert client.request(method, f'{ROOT}/{id}', headers=stranger,
                                  json={'name': 'Name'} if method == 'PUT' else None).status_code == 404
        for pid, tid in [(own_project['id'], foreign_tag['id']),
                         (foreign_project['id'], own_tag['id']), (str(uuid4()), foreign_tag['id'])]:
            assert client.request(method, f'{ROOT}/projects/{pid}/{tid}', headers=stranger).status_code == 404


@pytest.mark.parametrize('payload', [{}, {'name': ''}, {'name': '   '}, {'name': 'x' * 61},
                                     {'name': None}, {'name': 'ok', 'user_id': str(uuid4())}])
def test_invalid_payload(client, payload):
    owner = auth(client)
    record = tag(client, owner)
    assert client.post(ROOT, headers=owner, json=payload).status_code == 422
    assert client.put(f"{ROOT}/{record['id']}", headers=owner, json=payload).status_code == 422


def test_names_limits_and_idempotence_at_limit(client):
    owner = auth(client)
    p = project(client, owner)
    records = [tag(client, owner, f'Tag {index}') for index in range(50)]
    assert client.post(ROOT, headers=owner, json={'name': 'New'}).status_code == 409
    assert client.post(ROOT, headers=owner, json={'name': ' TAG 0 '}).status_code == 409
    assert client.put(f"{ROOT}/{records[1]['id']}", headers=owner, json={'name': 'tag 0'}).status_code == 409
    for record in records[:10]:
        assert client.put(f"{ROOT}/projects/{p['id']}/{record['id']}", headers=owner).status_code == 204
    assert client.put(f"{ROOT}/projects/{p['id']}/{records[0]['id']}", headers=owner).status_code == 204
    assert client.put(f"{ROOT}/projects/{p['id']}/{records[10]['id']}", headers=owner).status_code == 409


def test_duplicate_blueprint_and_archive_contracts(client):
    owner = auth(client)
    p, t = project(client, owner), tag(client, owner)
    path = f"/api/v1/projects/{p['id']}"
    assert client.put(f"{ROOT}/projects/{p['id']}/{t['id']}", headers=owner).status_code == 204
    for status in ('archived', 'active'):
        assert client.put(path, headers=owner, json={'status': status}).json()['tags'] == [t]
    copied = client.post(path + '/duplicate', headers=owner, json={'name': 'Cópia projeto'}).json()
    assert copied['tags'] == [t] and copied['id'] != p['id']
    blueprint = client.post('/api/v1/project-blueprints', headers=owner,
                            json={'source_project_id': p['id'], 'name': 'Modelo Tags'}).json()
    assert 'tags' not in blueprint['structure']
    generated = client.post(f"/api/v1/project-blueprints/{blueprint['id']}/projects", headers=owner,
                            json={'name': 'Do modelo'}).json()
    assert generated['tags'] == []
    assert client.delete(f"{ROOT}/projects/{copied['id']}/{t['id']}", headers=owner).status_code == 204
    assert client.get(path, headers=owner).json()['tags'] == [t]


def test_duplicate_rolls_back_tag_links(client, session_factory, monkeypatch):
    owner = auth(client)
    p, t = project(client, owner), tag(client, owner)
    assert client.put(f"{ROOT}/projects/{p['id']}/{t['id']}", headers=owner).status_code == 204
    assert client.post('/api/v1/chains', headers=owner,
                       json={'name': 'Chain tags', 'project_id': p['id']}).status_code == 201
    before = client.portal.call(snapshot, session_factory)

    def fail(**kwargs):
        raise RuntimeError('rollback after tag links')

    monkeypatch.setattr(service, 'PromptChain', fail)
    with pytest.raises(RuntimeError, match='rollback after tag links'):
        client.post(f"/api/v1/projects/{p['id']}/duplicate", headers=owner, json={'name': 'Cópia Tags'})
    assert client.portal.call(snapshot, session_factory) == before
