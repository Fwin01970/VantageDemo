--
-- PostgreSQL database dump
--

\restrict peCgJwtQQpv00WtZZdMdzZq2g8tkGGxwIO4ZijN3JXDgVmbTVdrstAL72uuiaMM

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA tenant_ad555ae3278747b9a00a57d1ac2d0c41;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: chat_conversations; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.chat_conversations (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    title text DEFAULT 'New conversation'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_messages; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.chat_messages (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    conversation_id uuid NOT NULL,
    role text NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    chart_data jsonb
);


--
-- Name: data_source_connections; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.data_source_connections (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    platform text NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    secret_ref text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: genie_query_parameter_fields; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_query_parameter_fields (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid,
    field_name text NOT NULL,
    options text[] NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: genie_question_templates; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_question_templates (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid,
    template text NOT NULL
);


--
-- Name: genie_suggested_questions; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_suggested_questions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid,
    question_text text NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: governance_reviews; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.governance_reviews (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid,
    question text NOT NULL,
    check_type text NOT NULL,
    reason text DEFAULT ''::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    decision_note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: local_secrets; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.local_secrets (
    secret_ref text NOT NULL,
    ciphertext text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pinned_items; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.pinned_items (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    source text NOT NULL,
    item_type text NOT NULL,
    title text NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: schema_annotations; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.schema_annotations (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    catalog_name text NOT NULL,
    schema_name text NOT NULL,
    table_name text NOT NULL,
    column_name text,
    note text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: use_cases; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.use_cases (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    category text NOT NULL,
    sample_question text NOT NULL,
    icon_key text DEFAULT 'trending-up'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    generated_sql text
);


--
-- Name: user_credentials; Type: TABLE; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.user_credentials (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    databricks_host text,
    databricks_warehouse_id text,
    databricks_genie_space_id text,
    databricks_catalog text,
    databricks_schema text,
    databricks_pat_secret_ref text,
    llm_provider text,
    llm_api_key_secret_ref text,
    last_validated_at timestamp with time zone,
    last_validation_ok boolean,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Data for Name: chat_conversations; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.chat_conversations (id, tenant_id, user_id, title, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: chat_messages; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.chat_messages (id, conversation_id, role, content, created_at, chart_data) FROM stdin;
\.


--
-- Data for Name: data_source_connections; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.data_source_connections (id, tenant_id, platform, config, secret_ref, is_active, created_at) FROM stdin;
\.


--
-- Data for Name: genie_query_parameter_fields; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_query_parameter_fields (id, tenant_id, user_id, field_name, options, display_order, created_at) FROM stdin;
\.


--
-- Data for Name: genie_question_templates; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_question_templates (id, tenant_id, user_id, template) FROM stdin;
\.


--
-- Data for Name: genie_suggested_questions; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_suggested_questions (id, tenant_id, user_id, question_text, display_order, created_at) FROM stdin;
\.


--
-- Data for Name: governance_reviews; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.governance_reviews (id, tenant_id, user_id, question, check_type, reason, status, reviewed_by, reviewed_at, decision_note, created_at) FROM stdin;
\.


--
-- Data for Name: local_secrets; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.local_secrets (secret_ref, ciphertext, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: pinned_items; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.pinned_items (id, tenant_id, user_id, source, item_type, title, payload, created_at) FROM stdin;
\.


--
-- Data for Name: schema_annotations; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.schema_annotations (id, tenant_id, catalog_name, schema_name, table_name, column_name, note, created_by, created_at) FROM stdin;
\.


--
-- Data for Name: use_cases; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.use_cases (id, tenant_id, title, description, category, sample_question, icon_key, created_at, generated_sql) FROM stdin;
\.


--
-- Data for Name: user_credentials; Type: TABLE DATA; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

COPY tenant_ad555ae3278747b9a00a57d1ac2d0c41.user_credentials (id, tenant_id, user_id, databricks_host, databricks_warehouse_id, databricks_genie_space_id, databricks_catalog, databricks_schema, databricks_pat_secret_ref, llm_provider, llm_api_key_secret_ref, last_validated_at, last_validation_ok, created_at, updated_at) FROM stdin;
\.


--
-- Name: chat_conversations chat_conversations_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.chat_conversations
    ADD CONSTRAINT chat_conversations_pkey PRIMARY KEY (id);


--
-- Name: chat_messages chat_messages_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.chat_messages
    ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id);


--
-- Name: data_source_connections data_source_connections_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.data_source_connections
    ADD CONSTRAINT data_source_connections_pkey PRIMARY KEY (id);


--
-- Name: genie_query_parameter_fields genie_query_parameter_fields_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_query_parameter_fields
    ADD CONSTRAINT genie_query_parameter_fields_pkey PRIMARY KEY (id);


--
-- Name: genie_question_templates genie_question_templates_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_question_templates
    ADD CONSTRAINT genie_question_templates_pkey PRIMARY KEY (id);


--
-- Name: genie_suggested_questions genie_suggested_questions_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_suggested_questions
    ADD CONSTRAINT genie_suggested_questions_pkey PRIMARY KEY (id);


--
-- Name: governance_reviews governance_reviews_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.governance_reviews
    ADD CONSTRAINT governance_reviews_pkey PRIMARY KEY (id);


--
-- Name: local_secrets local_secrets_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.local_secrets
    ADD CONSTRAINT local_secrets_pkey PRIMARY KEY (secret_ref);


--
-- Name: pinned_items pinned_items_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.pinned_items
    ADD CONSTRAINT pinned_items_pkey PRIMARY KEY (id);


--
-- Name: schema_annotations schema_annotations_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.schema_annotations
    ADD CONSTRAINT schema_annotations_pkey PRIMARY KEY (id);


--
-- Name: use_cases use_cases_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.use_cases
    ADD CONSTRAINT use_cases_pkey PRIMARY KEY (id);


--
-- Name: user_credentials user_credentials_pkey; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.user_credentials
    ADD CONSTRAINT user_credentials_pkey PRIMARY KEY (id);


--
-- Name: user_credentials user_credentials_user_id_key; Type: CONSTRAINT; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE ONLY tenant_ad555ae3278747b9a00a57d1ac2d0c41.user_credentials
    ADD CONSTRAINT user_credentials_user_id_key UNIQUE (user_id);


--
-- Name: genie_question_templates_scope_idx; Type: INDEX; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE UNIQUE INDEX genie_question_templates_scope_idx ON tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_question_templates USING btree (tenant_id, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid));


--
-- Name: user_credentials_user_id_idx; Type: INDEX; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE INDEX user_credentials_user_id_idx ON tenant_ad555ae3278747b9a00a57d1ac2d0c41.user_credentials USING btree (user_id);


--
-- Name: data_source_connections; Type: ROW SECURITY; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.data_source_connections ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_query_parameter_fields genie_fields_visible; Type: POLICY; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE POLICY genie_fields_visible ON tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_query_parameter_fields USING (((tenant_id = public.current_tenant_id_safe()) AND ((user_id = public.current_user_id_safe()) OR (user_id IS NULL))));


--
-- Name: genie_query_parameter_fields; Type: ROW SECURITY; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_query_parameter_fields ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_question_templates; Type: ROW SECURITY; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_question_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_suggested_questions; Type: ROW SECURITY; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_suggested_questions ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_suggested_questions genie_suggestions_visible; Type: POLICY; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE POLICY genie_suggestions_visible ON tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_suggested_questions USING (((tenant_id = public.current_tenant_id_safe()) AND ((user_id = public.current_user_id_safe()) OR (user_id IS NULL))));


--
-- Name: genie_question_templates genie_template_visible; Type: POLICY; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE POLICY genie_template_visible ON tenant_ad555ae3278747b9a00a57d1ac2d0c41.genie_question_templates USING (((tenant_id = public.current_tenant_id_safe()) AND ((user_id = public.current_user_id_safe()) OR (user_id IS NULL))));


--
-- Name: data_source_connections query_parameters_visible; Type: POLICY; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE POLICY query_parameters_visible ON tenant_ad555ae3278747b9a00a57d1ac2d0c41.data_source_connections USING ((tenant_id = public.current_tenant_id_safe()));


--
-- Name: user_credentials; Type: ROW SECURITY; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

ALTER TABLE tenant_ad555ae3278747b9a00a57d1ac2d0c41.user_credentials ENABLE ROW LEVEL SECURITY;

--
-- Name: user_credentials user_owns_credentials; Type: POLICY; Schema: tenant_ad555ae3278747b9a00a57d1ac2d0c41; Owner: -
--

CREATE POLICY user_owns_credentials ON tenant_ad555ae3278747b9a00a57d1ac2d0c41.user_credentials USING (((tenant_id = public.current_tenant_id_safe()) AND (user_id = public.current_user_id_safe())));


--
-- PostgreSQL database dump complete
--

\unrestrict peCgJwtQQpv00WtZZdMdzZq2g8tkGGxwIO4ZijN3JXDgVmbTVdrstAL72uuiaMM

