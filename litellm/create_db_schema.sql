-- 1. 유저 생성
CREATE ROLE litellm
  WITH LOGIN
  PASSWORD 'YourPasswordHere'
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT;

-- 2. 데이터베이스 생성
CREATE DATABASE litellm
  OWNER litellm
  ENCODING 'UTF8'
  TEMPLATE template0;

-- 3. litellm DB로 접속 전환
\c litellm

-- 4. 스키마 생성
CREATE SCHEMA IF NOT EXISTS litellm AUTHORIZATION litellm;

-- 5. 기본 search_path 설정
ALTER ROLE litellm IN DATABASE litellm
  SET search_path TO litellm, public;

-- 6. 연결 및 스키마 사용 권한
GRANT CONNECT ON DATABASE litellm TO litellm;
GRANT USAGE, CREATE ON SCHEMA litellm TO litellm;

-- 7. public 스키마는 필요 최소화
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO litellm;

-- 8. 혹시 이후 postgres 등 다른 계정이 객체를 만들 경우를 대비한 기본 권한
ALTER DEFAULT PRIVILEGES FOR ROLE litellm IN SCHEMA litellm
  GRANT ALL ON TABLES TO litellm;

ALTER DEFAULT PRIVILEGES FOR ROLE litellm IN SCHEMA litellm
  GRANT ALL ON SEQUENCES TO litellm;

ALTER DEFAULT PRIVILEGES FOR ROLE litellm IN SCHEMA litellm
  GRANT ALL ON FUNCTIONS TO litellm;
