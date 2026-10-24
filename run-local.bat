@echo off
setlocal
if not exist .env.local (
  echo Missing .env.local. Copy .env.example to .env.local and add your Supabase URL and anon key.
  pause
  exit /b 1
)
call npm install
if errorlevel 1 exit /b 1
call npm run dev
