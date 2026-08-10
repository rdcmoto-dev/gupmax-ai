import os

os.environ["DATABASE_URL"] = "postgresql+asyncpg://user:password@localhost:5432/gupmax_test"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-that-is-long-enough-for-tests"
os.environ["DEBUG"] = "false"
