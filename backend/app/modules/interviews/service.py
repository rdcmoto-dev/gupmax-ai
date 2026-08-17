from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.interviews.enums import InterviewStatus, QuestionType
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
from app.modules.prompt_engine.schemas import PromptGenerateRequest
from app.modules.users.model import User


class InterviewService:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = InterviewRepository(session)
        self.generator = DeterministicQuestionGenerator()

    async def start(self, user: User, data: InterviewCreateRequest) -> InterviewRead:
        questions = self.generator.generate(data.mode, data.category)
        interview = await self.repository.create(
            user_id=user.id,
            status=InterviewStatus.READY if not questions else InterviewStatus.ACTIVE,
            mode=data.mode,
            category=data.category,
            initial_request=data.initial_request,
            questions=[question.model_dump(mode="json") for question in questions],
            expires_at=self._now() + timedelta(days=7),
        )
        return self._read(interview)

    async def get(self, interview_id: UUID, user: User) -> InterviewRead:
        return self._read(await self._accessible(interview_id, user))

    async def answer(self, interview_id: UUID, user: User, data: InterviewAnswersRequest) -> InterviewRead:
        interview = await self._accessible(interview_id, user)
        if interview.status not in (InterviewStatus.ACTIVE, InterviewStatus.READY):
            self._conflict("Interview no longer accepts answers")
        questions = {question.key: question for question in self._questions(interview)}
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
        answered_keys = {answer.question_key for answer in interview.answers}
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
        questions = {question.key: question for question in self._questions(interview)}
        answers = {answer.question_key: answer.value for answer in interview.answers}
        direct = {"audience", "tone", "language", "constraints", "output_format"}
        context_lines = [
            f"{questions[key].text} {self._format(value)}"
            for key, value in answers.items()
            if key not in direct and key not in {"success_criteria", "include_examples"}
        ]
        instructions = []
        if value := answers.get("success_criteria"):
            instructions.append(f"Atenda aos seguintes critérios de sucesso: {self._format(value)}")
        if answers.get("include_examples") is True:
            instructions.append("Inclua exemplos relevantes na resposta.")
        constraints = self._lines(answers.get("constraints"))
        return PromptGenerateRequest(
            input=interview.initial_request,
            mode=interview.mode,
            category=interview.category,
            language=str(answers.get("language", "pt-BR")),
            tone=self._optional_string(answers.get("tone")),
            context="\n".join(context_lines) or None,
            audience=self._optional_string(answers.get("audience")),
            instructions=instructions,
            constraints=constraints,
            output_format=self._optional_string(answers.get("output_format")),
            additional_information=None,
            optimize_with_ai=False,
        )

    @staticmethod
    def _validate_answer(question: InterviewQuestion, value: Any) -> None:
        invalid = False
        if question.type in (QuestionType.TEXT, QuestionType.MULTILINE):
            invalid = not isinstance(value, str) or not value.strip() or len(value) > 4_000
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

    @staticmethod
    def _lines(value: Any) -> list[str]:
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
