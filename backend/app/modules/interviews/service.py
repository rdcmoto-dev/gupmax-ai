from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.interviews.enums import InterviewStatus, QuestionType
from app.modules.interviews.facts import DeterministicFactExtractor, FactSource, InterviewFact
from app.modules.interviews.model import InterviewSession
from app.modules.interviews.question_generator import DeterministicQuestionGenerator
from app.modules.interviews.repository import InterviewRepository
from app.modules.interviews.schemas import (
    InterviewAnswerRead,
    InterviewAnswersRequest,
    InterviewCompleteResponse,
    InterviewCreateRequest,
    InterviewProgress,
    InterviewQuestion,
    InterviewRead,
)
from app.modules.projects.model import ProjectStatus
from app.modules.projects.service import ProjectService
from app.modules.prompt_engine.schemas import PromptGenerateRequest
from app.modules.smart_profile.service import SmartProfileService
from app.modules.users.model import User


class InterviewService:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = InterviewRepository(session)
        self.generator = DeterministicQuestionGenerator()
        self.fact_extractor = DeterministicFactExtractor()

    async def start(self, user: User, data: InterviewCreateRequest) -> InterviewRead:
        profile = await SmartProfileService(self.repository.session).enabled(user.id)
        facts = self.fact_extractor.from_profile(profile) if profile is not None else {}
        if data.known_fields is not None and data.known_fields.project_id is not None:
            project = await ProjectService(self.repository.session).accessible(data.known_fields.project_id, user)
            if project.status == ProjectStatus.ARCHIVED:
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Archived project is read-only")
            if project.context:
                facts["context"] = InterviewFact(
                    value=project.context,
                    source=FactSource.PROJECT,
                    confidence=1.0,
                )
        facts.update(self.fact_extractor.extract(data.initial_request, data.category))
        if data.known_fields is not None:
            form_facts = self.fact_extractor.from_form(data.known_fields)
            for key, fact in form_facts.items():
                current = facts.get(key)
                if (
                    key not in {"language", "tone", "audience"}
                    or current is None
                    or current.source == FactSource.PROFILE
                ):
                    facts[key] = fact
        questions = self.generator.generate(data.mode, data.category, set(facts))
        interview = await self.repository.create(
            user_id=user.id,
            status=InterviewStatus.READY if not questions else InterviewStatus.ACTIVE,
            mode=data.mode,
            category=data.category,
            initial_request=data.initial_request,
            questions=[question.model_dump(mode="json") for question in questions],
            facts=self.fact_extractor.dump(facts),
            expires_at=self._now() + timedelta(days=7),
        )
        return self._read(interview)

    async def get(self, interview_id: UUID, user: User) -> InterviewRead:
        return self._read(await self._accessible(interview_id, user))

    async def answer(self, interview_id: UUID, user: User, data: InterviewAnswersRequest) -> InterviewRead:
        interview = await self._accessible(interview_id, user)
        if interview.status not in (InterviewStatus.ACTIVE, InterviewStatus.READY):
            self._conflict("Interview no longer accepts answers")
        questions = {question.key: question for question in self._all_questions(interview)}
        values: dict[str, Any] = {}
        for answer in data.answers:
            question = questions.get(answer.question_key)
            if question is None:
                raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Unknown question key")
            self._validate_answer(question, answer.value)
            values[answer.question_key] = answer.value
        interview = await self.repository.upsert_answers(interview, values)
        next_status = InterviewStatus.READY if self._is_ready(interview) else InterviewStatus.ACTIVE
        if interview.status != next_status:
            interview = await self.repository.update_status(interview, next_status)
        return self._read(interview)

    async def complete(self, interview_id: UUID, user: User) -> InterviewCompleteResponse:
        interview = await self._accessible(interview_id, user, allow_completed=True)
        if interview.status == InterviewStatus.COMPLETED:
            prompt_input = PromptGenerateRequest.model_validate(interview.structured_prompt)
            return InterviewCompleteResponse(interview=self._read(interview), prompt_input=prompt_input)
        if interview.status != InterviewStatus.READY:
            self._conflict("Interview still has required questions")
        prompt_input = self._build_prompt_input(interview)
        interview = await self.repository.complete(interview, prompt_input.model_dump(mode="json"), self._now())
        return InterviewCompleteResponse(interview=self._read(interview), prompt_input=prompt_input)

    async def _accessible(self, interview_id: UUID, user: User, *, allow_completed: bool = False) -> InterviewSession:
        interview = await self.repository.get_by_id(interview_id)
        if interview is None or interview.user_id != user.id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Interview not found")
        if interview.status not in (InterviewStatus.COMPLETED, InterviewStatus.EXPIRED) and self._expired(interview):
            interview = await self.repository.update_status(interview, InterviewStatus.EXPIRED)
        if interview.status == InterviewStatus.EXPIRED:
            self._conflict("Interview expired")
        if interview.status == InterviewStatus.COMPLETED and not allow_completed:
            return interview
        return interview

    def _read(self, interview: InterviewSession) -> InterviewRead:
        questions = self._questions(interview)
        question_keys = {question.key for question in questions}
        answered_keys = {answer.question_key for answer in interview.answers} & question_keys
        required_keys = {question.key for question in questions if question.required}
        structured = (
            PromptGenerateRequest.model_validate(interview.structured_prompt)
            if interview.structured_prompt is not None
            else None
        )
        return InterviewRead(
            id=interview.id,
            user_id=interview.user_id,
            status=interview.status,
            mode=interview.mode,
            category=interview.category,
            initial_request=interview.initial_request,
            questions=questions,
            answers=[InterviewAnswerRead.model_validate(answer) for answer in interview.answers],
            progress=InterviewProgress(
                answered=len(answered_keys),
                total=len(questions),
                required_answered=len(answered_keys & required_keys),
                required_total=len(required_keys),
            ),
            structured_prompt=structured,
            created_at=interview.created_at,
            updated_at=interview.updated_at,
            completed_at=interview.completed_at,
            expires_at=interview.expires_at,
        )

    def _is_ready(self, interview: InterviewSession) -> bool:
        required = {question.key for question in self._questions(interview) if question.required}
        answered = {answer.question_key for answer in interview.answers}
        return required <= answered

    def _build_prompt_input(self, interview: InterviewSession) -> PromptGenerateRequest:
        questions = {question.key: question for question in self._all_questions(interview)}
        facts = self.fact_extractor.load(interview.facts)
        answers = {answer.question_key: answer.value for answer in interview.answers}
        values = {key: fact.value for key, fact in facts.items()}
        values.update(answers)
        direct = {
            "audience",
            "tone",
            "language",
            "constraints",
            "output_format",
            "title",
            "role",
            "instructions",
            "additional_information",
            "provider",
            "model",
            "project_id",
            "target_ai",
        }
        context_lines = [
            f"{questions[key].text} {self._format(value)}"
            for key, value in answers.items()
            if key not in direct and key not in {"success_criteria", "include_examples"}
        ]
        context_lines.extend(
            self._fact_context(key, fact) for key, fact in facts.items() if key not in answers and key not in direct
        )
        instructions = list(values.get("instructions", []))
        if value := values.get("success_criteria"):
            instructions.append(f"Atenda aos seguintes critérios de sucesso: {self._format(value)}")
        if values.get("include_examples") is True:
            instructions.append("Inclua exemplos relevantes na resposta.")
        constraints = self._lines(values.get("constraints"))
        base_context = self._optional_string(values.get("context"))
        context = "\n".join([item for item in [base_context, *context_lines] if item]) or None
        return PromptGenerateRequest(
            input=interview.initial_request,
            mode=interview.mode,
            category=interview.category,
            language=str(values.get("language", "pt-BR")),
            tone=self._optional_string(values.get("tone")),
            title=self._optional_string(values.get("title")),
            context=context,
            audience=self._optional_string(values.get("audience")),
            role=self._optional_string(values.get("role")),
            instructions=instructions,
            constraints=constraints,
            output_format=self._optional_string(values.get("output_format")),
            additional_information=self._optional_string(values.get("additional_information")),
            provider=str(values.get("provider", "openai")),
            model=self._optional_string(values.get("model")),
            optimize_with_ai=values.get("optimize_with_ai") is True,
            project_id=values.get("project_id"),
            target_ai=values.get("target_ai", "generic"),
        )

    @staticmethod
    def _validate_answer(question: InterviewQuestion, value: Any) -> None:
        invalid = False
        if question.type in (QuestionType.TEXT, QuestionType.MULTILINE):
            invalid = (
                not isinstance(value, str)
                or not value.strip()
                or len(value) > 4_000
                or value.strip().casefold() == question.text.strip().casefold()
            )
        elif question.type == QuestionType.SINGLE_CHOICE:
            invalid = not isinstance(value, str) or value not in question.options
        elif question.type == QuestionType.MULTI_CHOICE:
            invalid = (
                not isinstance(value, list)
                or not value
                or any(not isinstance(item, str) or item not in question.options for item in value)
                or len(value) != len(set(value))
            )
        elif question.type == QuestionType.BOOLEAN:
            invalid = not isinstance(value, bool)
        if invalid:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Invalid answer value")

    @staticmethod
    def _questions(interview: InterviewSession) -> list[InterviewQuestion]:
        return [InterviewQuestion.model_validate(question) for question in interview.questions]

    def _all_questions(self, interview: InterviewSession) -> list[InterviewQuestion]:
        return self.generator.generate(interview.mode, interview.category)

    @staticmethod
    def _fact_context(key: str, fact: InterviewFact) -> str:
        labels = {
            "channel": "Canal/plataforma",
            "platform": "Plataforma",
            "duration": "Duração",
            "stack": "Stack",
        }
        value = fact.detail or InterviewService._format(fact.value)
        if fact.detail and fact.detail.casefold() != str(fact.value).casefold():
            value = f"{fact.detail} ({InterviewService._format(fact.value)})"
        return f"{labels.get(key, key.replace('_', ' ').title())}: {value}"

    @staticmethod
    def _lines(value: Any) -> list[str]:
        if isinstance(value, list) and all(isinstance(item, str) for item in value):
            return [item.strip() for item in value if item.strip()]
        if not isinstance(value, str):
            return []
        return [line.strip(" -") for line in value.splitlines() if line.strip(" -")]

    @staticmethod
    def _optional_string(value: Any) -> str | None:
        return value if isinstance(value, str) and value else None

    @staticmethod
    def _format(value: Any) -> str:
        if isinstance(value, list):
            return ", ".join(value)
        if isinstance(value, bool):
            return "sim" if value else "não"
        return str(value)

    @staticmethod
    def _conflict(detail: str) -> None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail)

    @staticmethod
    def _now() -> datetime:
        return datetime.now(UTC)

    def _expired(self, interview: InterviewSession) -> bool:
        expires_at = interview.expires_at
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=UTC)
        return expires_at <= self._now()
