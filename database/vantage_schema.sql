--
-- PostgreSQL database dump
--

\restrict 3TE4Q8WozSMU0DQS5MBkp76LOYRW0LGa7B7G5drm2Fl11KEhlU0xL5l5GJwiQyZ

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
-- Name: tenant_11111111111111111111111111111111; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA tenant_11111111111111111111111111111111;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: chat_conversations; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.chat_conversations (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    title text DEFAULT 'New conversation'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_messages; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.chat_messages (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    conversation_id uuid NOT NULL,
    role text NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    chart_data jsonb
);


--
-- Name: data_source_connections; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.data_source_connections (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    platform text NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    secret_ref text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: genie_query_parameter_fields; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.genie_query_parameter_fields (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid,
    field_name text NOT NULL,
    options text[] NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: genie_question_templates; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.genie_question_templates (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid,
    template text NOT NULL
);


--
-- Name: genie_suggested_questions; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.genie_suggested_questions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid,
    question_text text NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: governance_reviews; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.governance_reviews (
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
-- Name: local_secrets; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.local_secrets (
    secret_ref text NOT NULL,
    ciphertext text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pinned_items; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.pinned_items (
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
-- Name: schema_annotations; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.schema_annotations (
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
-- Name: use_cases; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.use_cases (
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
-- Name: user_credentials; Type: TABLE; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE TABLE tenant_11111111111111111111111111111111.user_credentials (
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
-- Data for Name: chat_conversations; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.chat_conversations (id, tenant_id, user_id, title, created_at, updated_at) FROM stdin;
3fc9c847-c0a6-4dac-b723-08afbbd2a14b	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me top 3 highest paid claims with asked amount.	2026-08-22 22:58:46.913378+05:30	2026-08-22 22:58:50.901548+05:30
f1d69642-7515-405b-a1a3-8db7981c8b8e	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me the loss ratio trend by region for this year	2026-08-25 13:06:59.72252+05:30	2026-08-25 13:07:05.697583+05:30
ab022105-41f3-4e6d-8d5f-ad608ce3a976	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me the loss ratio trend by region for this year	2026-08-23 11:41:58.172439+05:30	2026-08-23 11:42:10.829018+05:30
db88a950-ec46-4a07-a4a4-a2268b3a0651	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me loss ratio of this year of all segment	2026-08-19 00:53:16.810258+05:30	2026-08-19 01:12:27.46215+05:30
54e2d74c-a47d-4cb3-92a5-e45c3a036573	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me loss ratio of this year of all segment	2026-08-19 02:04:06.889681+05:30	2026-08-19 02:04:11.115719+05:30
6915aad4-7668-49ee-a21c-11b61e0b7b1a	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	What is our average settlement time this quarter?	2026-08-23 11:59:38.47619+05:30	2026-08-23 11:59:44.389888+05:30
e4f799ac-3ed0-497e-adfd-60c1d0b7ab81	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me the loss ratio trend by region for this year	2026-08-19 02:19:53.82981+05:30	2026-08-19 02:30:42.054311+05:30
4ef0e300-7696-4667-92b6-40876a060c6c	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	What is our average settlement time this quarter?	2026-08-19 02:33:53.549671+05:30	2026-08-19 02:33:53.555918+05:30
277b6db7-71f7-4c1c-bc8e-b606ea9c8ea4	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me the loss ratio trend by region for this year	2026-08-23 12:02:25.032477+05:30	2026-08-23 12:16:55.614166+05:30
d7025717-02cd-4c1b-a105-9276e96e7cb1	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	"Which product lines have the highest loss ratios and lowest…	2026-08-26 00:13:57.817164+05:30	2026-08-26 00:13:57.89454+05:30
673bca21-44c6-4d7e-9d59-e154d8102cc3	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me the loss ratio trend by region for this year	2026-08-24 01:35:20.258366+05:30	2026-08-24 01:35:29.205964+05:30
b405503d-c770-4caf-a29d-43d89bcb3f96	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me the loss ratio trend by region for this year	2026-08-24 16:57:47.043084+05:30	2026-08-24 16:57:57.401306+05:30
54bc73ad-768b-493c-bdb5-9419648b2df8	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	combine claims data year wise and show in barchart	2026-08-21 00:48:17.588825+05:30	2026-08-21 02:19:38.149875+05:30
c0342100-c913-407d-a432-a2e5fc137396	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Anomaly detection	2026-08-21 02:45:37.54563+05:30	2026-08-21 02:45:42.4986+05:30
3a0a3d09-b19a-4263-9294-c5dd57d712c9	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Anomaly detection	2026-08-21 02:46:48.335628+05:30	2026-08-21 02:55:24.538847+05:30
a240e586-e641-4fde-bc6c-05e91ba7386e	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	"Which customers are at high risk of churn this quarter, and…	2026-08-24 17:11:27.697892+05:30	2026-08-24 17:11:32.565283+05:30
521dc8ca-3027-46c4-b6c1-30d6fb7b68aa	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	What is our average settlement time this quarter?	2026-08-24 17:15:49.999793+05:30	2026-08-24 17:15:54.441191+05:30
54adadb0-0beb-41bc-9631-bd743b20e5a6	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	"Which product lines have the highest loss ratios and lowest…	2026-08-24 17:19:00.981086+05:30	2026-08-24 17:19:09.907292+05:30
a88b9077-6862-45b3-9a91-b608afd6ae4c	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Virat kohlis highest score in 2026	2026-08-21 14:58:54.659856+05:30	2026-08-22 01:55:38.067615+05:30
4b53bf1f-c961-4eea-acc8-d142ac6a28fd	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me loss ratio of all region	2026-08-25 12:51:19.670598+05:30	2026-08-25 12:51:25.873329+05:30
d24a502a-ccc9-4b81-87fe-9f86f5715624	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me top 3 highest paid claims with asked amount.	2026-08-22 22:56:32.131302+05:30	2026-08-22 22:56:37.456848+05:30
04ebdbd0-92ac-41e3-91f1-efd1d74cbe20	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	What is the projected revenue for the next quarter, and whic…	2026-08-25 12:57:15.419198+05:30	2026-08-25 12:57:21.523819+05:30
ab75dd4f-baa4-43c0-815d-e283f2a51781	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Which customers are at high risk of churn this quarter, and …	2026-08-25 13:06:12.462829+05:30	2026-08-25 13:06:17.478365+05:30
c1d50da2-c573-44e8-bf97-708026c54acf	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me the loss ratio trend by region for this year	2026-08-31 14:20:12.239963+05:30	2026-08-31 14:20:12.251055+05:30
16a64e22-63b0-49f7-921d-a30d4403ec44	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Are there any unusual claims this month?	2026-08-31 14:20:18.609335+05:30	2026-08-31 14:20:18.617895+05:30
d42b3003-3bb3-4686-ada3-8de9567b107e	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me the loss ratio trend by region for this year	2026-08-31 14:21:11.511707+05:30	2026-08-31 14:21:11.529774+05:30
eedbac44-1d41-4aef-9e94-bea86ddf2eb3	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	Show me the loss ratio trend by region for this year	2026-09-01 21:45:24.94567+05:30	2026-09-01 21:45:25.013458+05:30
\.


--
-- Data for Name: chat_messages; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.chat_messages (id, conversation_id, role, content, created_at, chart_data) FROM stdin;
e2624574-e80a-49e6-a29f-8e813fa88c0a	db88a950-ec46-4a07-a4a4-a2268b3a0651	user	Show me loss ratio of this year of all segment	2026-08-19 00:53:22.037568+05:30	\N
55436649-0f92-42c8-ba75-5a6a29406bfc	db88a950-ec46-4a07-a4a4-a2268b3a0651	assistant		2026-08-19 00:53:22.080194+05:30	\N
197293a3-d167-4c9f-850e-ee6816346be2	db88a950-ec46-4a07-a4a4-a2268b3a0651	user	Show me loss ratio of this year of all segment	2026-08-19 01:01:17.495467+05:30	\N
662fb358-4c33-4bb0-a672-7d4f0db47e05	db88a950-ec46-4a07-a4a4-a2268b3a0651	user	Show me loss ratio of this year of all segment	2026-08-19 01:12:27.46215+05:30	\N
a8a2d6c4-baba-4828-8b09-e4a56f484198	54e2d74c-a47d-4cb3-92a5-e45c3a036573	user	Show me loss ratio of this year of all segment	2026-08-19 02:04:11.115719+05:30	\N
ba471264-ef9b-4c0c-8dd0-38afe51790cf	e4f799ac-3ed0-497e-adfd-60c1d0b7ab81	user	Show me the loss ratio trend by region for this year	2026-08-19 02:19:53.846442+05:30	\N
ea4a3fde-a96d-4740-9edf-9db226f9ce4b	e4f799ac-3ed0-497e-adfd-60c1d0b7ab81	user	Show me the loss ratio trend by region for this year	2026-08-19 02:30:42.054311+05:30	\N
dd256e65-f398-4f06-a064-d20af6db9566	4ef0e300-7696-4667-92b6-40876a060c6c	user	What is our average settlement time this quarter?	2026-08-19 02:33:53.555918+05:30	\N
cab73457-c5d9-40bb-888c-d4994f9dbd58	54bc73ad-768b-493c-bdb5-9419648b2df8	user	combine claims data year wise and show in barchart 	2026-08-21 00:48:23.245403+05:30	\N
abfc1105-4fb3-44e2-be3c-a5d2ece83fb4	54bc73ad-768b-493c-bdb5-9419648b2df8	assistant	Here is the summary of claims data aggregated year-wise based on loss date:\n\n### Claims Summary by Year\n\n| Year | Total Claims | Total Claim Amount | Total Paid Amount | Total Reserved Amount |\n| :--- | :--- | :--- | :--- | :--- |\n| **2024** | 81,326 | $12.21B | $7.32B | $4.89B |\n| **2025** | 129,715 | $19.49B | $11.68B | $7.80B |\n| **2026** | 53,941 | $8.12B | $4.86B | $3.25B |\n\n---\n\n### Year-wise Total Claim Amount (Visual Representation)\n\n```text\n2024  [███████████████████████]  $12.21B  (81,326 claims)\n2025  [█████████████████████████████████████]  $19.49B  (129,715 claims)\n2026  [█████████████]  $8.12B   (53,941 claims)\n```\n\n### Key Highlights:\n- **2025** represents the peak volume and financial impact with **129,715 claims** totaling **$19.49 Billion**.\n- **2024** saw **81,326 claims** amounting to **$12.21 Billion**.\n- **2026** reflects current partial/recorded claims totaling **53,941 claims** amounting to **$8.12 Billion**.	2026-08-21 00:48:23.287078+05:30	\N
efbddf47-02b9-4475-a5b6-745c2c39979b	54bc73ad-768b-493c-bdb5-9419648b2df8	user	combine claims data year wise and show in barchart 	2026-08-21 01:20:34.13254+05:30	\N
191530b2-9111-4dbe-a111-6b2011f90eac	54bc73ad-768b-493c-bdb5-9419648b2df8	user	combine claims data year wise and show in barchart 	2026-08-21 01:22:26.722906+05:30	\N
6d5f3c64-db4a-4c86-823d-9a7e1c4326bd	54bc73ad-768b-493c-bdb5-9419648b2df8	user	combine claims data year wise and show in barchart 	2026-08-21 01:24:24.540035+05:30	\N
4804566d-09a9-495d-8dae-0f99909dc93e	54bc73ad-768b-493c-bdb5-9419648b2df8	user	combine claims data year wise and show in barchart 	2026-08-21 01:25:57.488374+05:30	\N
71daa7c8-929d-4a7f-9703-f5f374ba151f	54bc73ad-768b-493c-bdb5-9419648b2df8	assistant	Here is the year-wise breakdown of claims data based on loss dates from company records:\n\n### Claims Summary by Year\n\n| Year | Total Claims | Total Claim Amount | Total Paid Amount | Total Reserved Amount |\n| :--- | :--- | :--- | :--- | :--- |\n| **2024** | 81,326 | $12,212,520,403.07 ($12.21B) | $7,320,837,387.24 ($7.32B) | $4,891,683,015.83 ($4.89B) |\n| **2025** | 129,715 | $19,487,022,237.00 ($19.49B) | $11,683,722,287.11 ($11.68B) | $7,803,299,949.89 ($7.80B) |\n| **2026** | 53,941 | $8,115,481,465.08 ($8.12B) | $4,864,973,273.70 ($4.86B) | $3,250,508,191.38 ($3.25B) |\n\n---\n\n### Key Takeaways\n\n- **2025 Peak:** 2025 accounts for the highest claim volume and financial load with **129,715 claims** totaling **$19.49 Billion** in total claim amounts.\n- **2024 Baseline:** 2024 recorded **81,326 claims** with **$12.21 Billion** total claim amount and **$7.32 Billion** paid out.\n- **2026 Partial Total:** Year 2026 currently reflects **53,941 claims** with a total claim value of **$8.12 Billion**.	2026-08-21 01:26:02.148161+05:30	{"rows": [["2024", "81326", "12212520403.07", "7320837387.24", "4891683015.83"], ["2025", "129715", "19487022237.00", "11683722287.11", "7803299949.89"], ["2026", "53941", "8115481465.08", "4864973273.70", "3250508191.38"]], "columns": ["YearNum", "TotalClaims", "TotalClaimAmount", "TotalPaidAmount", "TotalReservedAmount"]}
465a9fa4-204f-4d23-a11e-2453cfeeb0de	54bc73ad-768b-493c-bdb5-9419648b2df8	user	Show me top 3 highest paid claims with asked amount.	2026-08-21 02:19:32.519357+05:30	\N
5d88d040-b1db-4422-ab47-c9af20319419	54bc73ad-768b-493c-bdb5-9419648b2df8	assistant	Here are the top 3 highest paid claims along with their asked (claimed) amounts from company records:\n\n### Top 3 Highest Paid Claims\n\n| Claim ID | Policy Number | Claimant Name | Product Line | Asked Amount (Claim Amount) | Paid Amount |\n| :--- | :--- | :--- | :--- | :--- | :--- |\n| **53789** | POL-CAS-LA-2024-00048351 | Ana Hill | Casualty | $249,785.89 | **$224,725.87** |\n| **179734** | POL-PROP-OH-2025-00280683 | Dean Donovan | Property | $249,843.69 | **$224,609.47** |\n| **204420** | POL-CAS-PA-2025-00401757 | Karen Morales DDS | Casualty | $249,449.10 | **$224,494.72** |	2026-08-21 02:19:38.149875+05:30	{"rows": [["53789", "POL-CAS-LA-2024-00048351", "Ana Hill", "Casualty", "249785.89", "224725.87"], ["179734", "POL-PROP-OH-2025-00280683", "Dean Donovan", "Property", "249843.69", "224609.47"], ["204420", "POL-CAS-PA-2025-00401757", "Karen Morales DDS", "Casualty", "249449.10", "224494.72"]], "columns": ["FactClaimID", "PolicyNumber", "ClaimantName", "ProductLineName", "AskedAmount", "PaidAmount"]}
6d0b10ca-fc25-4af8-be36-4a520788cf09	c0342100-c913-407d-a432-a2e5fc137396	user	Anomaly detection 	2026-08-21 02:45:42.4986+05:30	\N
9ee5fd1e-07af-42c0-b940-f879996f312d	3a0a3d09-b19a-4263-9294-c5dd57d712c9	user	Anomaly detection 	2026-08-21 02:46:52.248313+05:30	\N
05aaf513-3990-4a05-b460-94759f2c07a3	3a0a3d09-b19a-4263-9294-c5dd57d712c9	user	Anomaly detection 	2026-08-21 02:55:24.538847+05:30	\N
9ac64d90-aafd-4387-b330-2e0fccf1484e	a88b9077-6862-45b3-9a91-b608afd6ae4c	user	Virat kohlis highest score in 2026	2026-08-21 14:58:54.678799+05:30	\N
7c64a288-bb54-4c89-9ee2-9d7f5d3f0ed0	a88b9077-6862-45b3-9a91-b608afd6ae4c	user	Virat kohlis highest score in 2026	2026-08-22 00:08:49.362238+05:30	\N
a2a3ed54-0ffb-4743-a53c-288dd3e0561f	a88b9077-6862-45b3-9a91-b608afd6ae4c	assistant	This is a general sports knowledge question and is not related to ABC Insurance's company data warehouse.\n\nAs of 2026, Virat Kohli's highest score in international or competitive cricket during 2026 would depend on official match records from the ongoing cricket season. \n\nIf you are looking for specific historical statistics or individual match performance figures for Virat Kohli across formats (Test, ODI, T20/IPL), please specify the particular tournament or match format you are interested in!	2026-08-22 00:08:53.135148+05:30	\N
3d86bf2d-86b3-454a-8004-0407e4f012d5	a88b9077-6862-45b3-9a91-b608afd6ae4c	user	show me my 10th result	2026-08-22 00:52:36.20975+05:30	\N
bb5214b1-e98b-43fe-a316-cba169c160a3	a88b9077-6862-45b3-9a91-b608afd6ae4c	assistant	I do not have access to personal academic records or board examination results (such as CBSE, ICSE, or State Board 10th class results). \n\nIf you are asking about business analytics or company records for ABC Insurance (such as specific policy records, claims data, broker lists, or financial reports), please let me know what data you would like to view!	2026-08-22 00:52:39.628251+05:30	\N
5f2809c6-93c1-483a-a4d8-598615dce2da	a88b9077-6862-45b3-9a91-b608afd6ae4c	user	Can I delete the schema from attached cataloug.	2026-08-22 00:54:21.738737+05:30	\N
4c353cdb-8e42-4fe6-bc0a-3421fa0624d7	a88b9077-6862-45b3-9a91-b608afd6ae4c	user	according to previous data show me prediction of loss ratio of 2027	2026-08-22 01:35:11.037405+05:30	\N
eb88f0cb-6f5d-42c9-b6e0-37bc17e85a73	a88b9077-6862-45b3-9a91-b608afd6ae4c	assistant	**No, you cannot delete a schema through this environment.**\n\nHere is why:\n\n1. **Read-Only Access:** The database interface provided here is strictly **read-only**. Only `SELECT` statements are allowed. Modifying or administrative commands like `DROP SCHEMA`, `DROP TABLE`, or `DELETE` are blocked.\n2. **Databricks Unity Catalog Permissions:** In Databricks, deleting a schema (`DROP SCHEMA <catalog>.<schema_name>`) requires specific administrative permissions:\n   - You must be the owner of the schema, an owner of the parent catalog, or a Databricks Metastore Admin.\n   - You must have the `USE CATALOG` and `USE SCHEMA` privileges, along with schema ownership or explicit drop permissions.\n   - If the schema contains tables or volumes, `DROP SCHEMA CASCADE` is required, which needs appropriate permissions on all underlying objects.\n\nIf you need to manage or remove schemas in Databricks, you must log into the Databricks Workspace UI or CLI with an administrator account that has schema ownership privileges.	2026-08-22 00:54:26.804544+05:30	\N
498e641e-2394-4b31-8d70-47d20e77eda1	a88b9077-6862-45b3-9a91-b608afd6ae4c	user	according to previous data show me prediction of loss ratio of 2027	2026-08-22 01:20:27.658631+05:30	\N
b4073c6f-9c57-459f-936f-be545e4e91bd	a88b9077-6862-45b3-9a91-b608afd6ae4c	user	according to previous data show me prediction of loss ratio of 2027	2026-08-22 01:55:34.074293+05:30	\N
36732cc7-6acd-4133-91a9-408b2aef6a92	a88b9077-6862-45b3-9a91-b608afd6ae4c	assistant	Here is the analysis of historical loss ratios alongside a projection for 2027 based on historical trends in company data.\n\n---\n\n### 1. Historical Data (Paid-Basis Loss Ratio)\n\nBelow are the historical actuals retrieved from `poc_alliedworld.curated_gold.vw_broker_loss_ratio`:\n\n| Year | Total Paid Loss | Total Premium | Paid Loss Ratio |\n| :--- | :--- | :--- | :--- |\n| **2024** | $7,320,837,387.24 | $93,499.42 | 7,829,821.00% |\n| **2025** | $11,683,722,287.11 | $182,438.21 | 6,404,207.96% |\n| **2026** | $4,864,973,273.70 | $14,807.45 | 32,854,909.03% |\n\n---\n\n### 2. 2027 Loss Ratio Projection\n\n> **AI projection, not verified against actual data**\n\n* **Projected 2027 Paid Loss Ratio:** ~15,696,312.66% (3-year weighted linear trend model)\n* **Projected Paid Loss:** ~$7.96 Billion\n* **Projected Premium:** ~$96,915.03\n\n---\n\n### 3. Key Observations & Caveats\n\n* **Data Disparity:** The historical records show very high paid losses relative to the premium recorded in this specific view, resulting in extremely high loss ratio percentages.\n* **Trend Dynamics:** Between 2024 and 2025, the loss ratio dropped by ~18.2%, followed by a sharp increase in 2026 due to significantly lower recorded premiums in that calendar year.\n* **Model Limitation:** This forecast uses a basic statistical linear extrapolation of the 2024–2026 data points. Actual 2027 performance will depend on rate adjustments, underwriting changes, and updated premium volume.	2026-08-22 01:55:38.067615+05:30	{"rows": [["2024", "7320837387.24", "93499.4221", "7829821.00"], ["2025", "11683722287.11", "182438.2088", "6404207.96"], ["2026", "4864973273.70", "14807.4471", "32854909.03"]], "columns": ["YearNum", "TotalPaid", "TotalPremium", "OverallLossRatioPct"]}
075e0d28-fb56-4609-86a4-9ef9bff7dba1	d24a502a-ccc9-4b81-87fe-9f86f5715624	user	Show me top 3 highest paid claims with asked amount.	2026-08-22 22:56:37.456848+05:30	\N
6fc991a7-8b07-4d6d-b4ce-a7dbfa37e57a	3fc9c847-c0a6-4dac-b723-08afbbd2a14b	user	Show me top 3 highest paid claims with asked amount.	2026-08-22 22:58:50.901548+05:30	\N
70df394d-5158-4814-ba31-d90f214295b5	ab022105-41f3-4e6d-8d5f-ad608ce3a976	user	Show me the loss ratio trend by region for this year	2026-08-23 11:42:10.796794+05:30	\N
02deab64-98ac-4139-86ee-c1ac5fa4d369	ab022105-41f3-4e6d-8d5f-ad608ce3a976	assistant	### Loss Ratio Trend by Region (2024 – 2026)\n\nBased on company records, the latest calendar year available in the data warehouse is **2026**. Below is the regional loss ratio performance trend across recent years, followed by the **2026 quarterly trend**.\n\n---\n\n### 1. Annual Regional Loss Ratio Trend (2024 – 2026)\n\n*Figures based on canonical Paid Claims vs. Earned/Written Premium in `vw_broker_loss_ratio`.*\n\n| Region | Year | Total Paid Losses ($) | Total Premium ($) | Paid Loss Ratio (%) |\n| :--- | :---: | :---: | :---: | :---: |\n| **Midwest** | 2024 | $1,842,793,661.74 | $23,566.18 | 7,819,653.48% |\n| **Midwest** | 2025 | $2,971,603,979.16 | $46,009.59 | 6,458,662.85% |\n| **Midwest** | 2026 | $1,224,248,075.42 | $3,714.34 | 32,960,015.88% |\n| **Northeast** | 2024 | $1,401,443,166.59 | $17,753.59 | 7,893,856.08% |\n| **Northeast** | 2025 | $2,184,869,040.12 | $34,407.69 | 6,349,943.98% |\n| **Northeast** | 2026 | $921,880,019.77 | $2,808.76 | 32,821,545.61% |\n| **South** | 2024 | $2,237,348,352.09 | $28,532.04 | 7,841,528.41% |\n| **South** | 2025 | $3,594,006,253.64 | $55,875.26 | 6,432,195.55% |\n| **South** | 2026 | $1,478,257,396.29 | $4,520.17 | 32,703,552.16% |\n| **West** | 2024 | $1,839,252,206.82 | $23,647.60 | 7,777,753.17% |\n| **West** | 2025 | $2,933,243,014.19 | $46,145.67 | 6,356,485.97% |\n| **West** | 2026 | $1,240,587,782.22 | $3,764.17 | 32,957,844.58% |\n\n---\n\n### 2. 2026 Quarterly Trend by Region (Incurred Basis)\n\n*Figures based on `vw_loss_ratio_by_coverage_region_quarter` for 2026.*\n\n| Region | Quarter | Total Incurred Loss ($) | Total Earned Premium ($) | Loss Ratio (%) |\n| :--- | :---: | :---: | :---: | :---: |\n| **Midwest** | Q1 | $1,326,778,405.28 | $31,790,231.56 | 4,173.54% |\n| **Midwest** | Q2 | $714,157,519.62 | *Pending* | N/A |\n| **Northeast** | Q1 | $986,836,617.96 | $23,908,282.64 | 4,127.59% |\n| **Northeast** | Q2 | $551,710,685.14 | *Pending* | N/A |\n| **South** | Q1 | $1,592,123,660.57 | $38,605,098.73 | 4,124.13% |\n| **South** | Q2 | $871,872,017.33 | *Pending* | N/A |\n| **West** | Q1 | $1,360,291,520.18 | $32,017,054.10 | 4,248.65% |\n| **West** | Q2 | $711,711,039.00 | *Pending* | N/A |\n\n---\n\n### Key Takeaways\n1. **Regional Consistency:** Loss ratios remain consistent across regions within each period, with the **South** generating the largest absolute loss volume ($1.48B paid in 2026 YTD), followed by the **West** ($1.24B) and **Midwest** ($1.22B).\n2. **Quarterly Trajectory:** Incurred losses peaked in Q1 2026 across all regions and declined slightly in Q2 2026.	2026-08-23 11:42:10.829018+05:30	{"rows": [["Midwest", "2024", "1842793661.74", "23566.1806", "7819653.48"], ["Midwest", "2025", "2971603979.16", "46009.5851", "6458662.85"], ["Midwest", "2026", "1224248075.42", "3714.3431", "32960015.88"], ["Northeast", "2024", "1401443166.59", "17753.5941", "7893856.08"], ["Northeast", "2025", "2184869040.12", "34407.6900", "6349943.98"], ["Northeast", "2026", "921880019.77", "2808.7648", "32821545.61"], ["South", "2024", "2237348352.09", "28532.0442", "7841528.41"], ["South", "2025", "3594006253.64", "55875.2641", "6432195.55"], ["South", "2026", "1478257396.29", "4520.1738", "32703552.16"], ["West", "2024", "1839252206.82", "23647.6032", "7777753.17"], ["West", "2025", "2933243014.19", "46145.6696", "6356485.97"], ["West", "2026", "1240587782.22", "3764.1654", "32957844.58"]], "columns": ["RegionName", "YearNum", "TotalPaid", "TotalPremium", "LossRatioPct"]}
8a40fe7b-41b2-4658-ad24-23b39a8a9d5a	6915aad4-7668-49ee-a21c-11b61e0b7b1a	user	What is our average settlement time this quarter?	2026-08-23 11:59:44.389888+05:30	\N
3f39aa90-cb28-4a3c-93ee-4e454d4e26ed	277b6db7-71f7-4c1c-bc8e-b606ea9c8ea4	user	Show me the loss ratio trend by region for this year	2026-08-23 12:02:30.207053+05:30	\N
9a8bb828-e8a3-456a-bcb3-81826a678ca7	277b6db7-71f7-4c1c-bc8e-b606ea9c8ea4	user	"Which customers are at high risk of churn this quarter, and what are the top factors contributing to the risk?"	2026-08-23 12:16:55.614166+05:30	\N
0c0eae97-7e18-4ad6-b4f9-a0acc3292b5b	673bca21-44c6-4d7e-9d59-e154d8102cc3	user	Show me the loss ratio trend by region for this year	2026-08-24 01:35:29.205964+05:30	\N
6e968bcf-308d-4073-9ce0-a1b548eeda03	b405503d-c770-4caf-a29d-43d89bcb3f96	user	Show me the loss ratio trend by region for this year	2026-08-24 16:57:57.349353+05:30	\N
4464fc20-3623-4657-8a0b-ac87ed85ee43	b405503d-c770-4caf-a29d-43d89bcb3f96	assistant	### Regional Loss and Performance Trend (Current Year: 2026)\n\n*Data Source: Real company data pulled directly from the Databricks curated warehouse (`poc_alliedworld.curated_gold`).*\n\nIn the company's dataset, the current year recorded is **2026**. Below is the detailed breakdown of quarterly loss activity and total paid amounts across all regions for 2026, followed by historical multi-year comparisons.\n\n---\n\n### 1. 2026 YTD Regional Summary\n\n across all four geographic regions:\n\n| Region | 2026 YTD Total Paid Loss | Q1 2026 Incurred Loss | Q1 2026 Earned Premium | Q2 2026 Incurred Loss |\n| :--- | :--- | :--- | :--- | :--- |\n| **South** | $1,478,257,396.29 | $1,592,123,660.57 | $38,605,098.73 | $871,872,017.33 |\n| **West** | $1,240,587,782.22 | $1,360,291,520.18 | $32,017,054.10 | $711,711,039.00 |\n| **Midwest** | $1,224,248,075.42 | $1,326,778,405.28 | $31,790,231.56 | $714,157,519.62 |\n| **Northeast** | $921,880,019.77 | $986,836,617.96 | $23,908,282.64 | $551,710,685.14 |\n\n---\n\n### 2. Multi-Year Regional Loss Comparison (2024 – 2026 YTD)\n\nTo put this year's trend into historical context, here is how total paid claims have evolved by region over the past three years:\n\n| Region | 2024 Total Paid Loss | 2025 Total Paid Loss | 2026 YTD Paid Loss |\n| :--- | :--- | :--- | :--- |\n| **South** | $2,237,348,352.09 | $3,594,006,253.64 | $1,478,257,396.29 |\n| **Midwest** | $1,842,793,661.74 | $2,971,603,979.16 | $1,224,248,075.42 |\n| **West** | $1,839,252,206.82 | $2,933,243,014.19 | $1,240,587,782.22 |\n| **Northeast** | $1,401,443,166.59 | $2,184,869,040.12 | $921,880,019.77 |\n\n---\n\n### Key Takeaways\n\n- **Highest Claim Activity**: The **South** region consistently experiences the highest claim amounts (both paid and incurred), representing over 30% of total loss volume in 2026 YTD.\n- **Lowest Claim Activity**: The **Northeast** region maintains the lowest overall loss volume across all periods examined.\n- **Quarterly Movement**: Incurred losses peaked in Q1 2026 across all regions and show lower recorded totals in Q2 2026 as late-quarter figures continue to settle.	2026-08-24 16:57:57.401306+05:30	{"rows": [["Midwest", "2026", "1", "1326778405.28", "31790231.56", "4173.54"], ["Northeast", "2026", "1", "986836617.96", "23908282.64", "4127.59"], ["South", "2026", "1", "1592123660.57", "38605098.73", "4124.13"], ["West", "2026", "1", "1360291520.18", "32017054.10", "4248.65"], ["Midwest", "2026", "2", "714157519.62", null, "0.00"], ["Northeast", "2026", "2", "551710685.14", null, "0.00"], ["South", "2026", "2", "871872017.33", null, "0.00"], ["West", "2026", "2", "711711039.00", null, "0.00"]], "columns": ["RegionName", "YearNum", "QuarterNum", "TotalIncurredLoss", "TotalEarnedPremium", "LossRatioPct"]}
a7c44d05-e6de-4e08-8229-1880fc78a052	a240e586-e641-4fde-bc6c-05e91ba7386e	user	"Which customers are at high risk of churn this quarter, and what are the top factors contributing to the risk?"	2026-08-24 17:11:32.535629+05:30	\N
79e7f906-c3f5-46ea-a87f-34eacd6d3faa	a240e586-e641-4fde-bc6c-05e91ba7386e	assistant	### Data Availability Summary\n\nIndividual customer-level **churn risk prediction scores** for the current quarter are not directly stored in the data warehouse. However, historical policy lifecycle records from `poc_alliedworld.curated_gold.factpolicylifecycle` show the following policy event distribution:\n\n| Lifecycle Event Type | Event Count |\n| :--- | :--- |\n| **Issued** | 462,726 |\n| **Renewed** | 75,991 |\n| **Cancelled** | 63,589 |\n| **Reinstated** | 33,901 |\n\n---\n\n### Key Risk Factors Contributing to Policyholder Churn\n\nBased on insurance analytics best practices and operational data in the warehouse, the primary drivers of policy cancellation and non-renewal include:\n\n1. **Slow Claim Settlement Times (SLA Delays):**\n   * *Impact:* Prolonged claim settlement duration directly reduces customer satisfaction and renewal intent.\n   * *Indicator:* States and product lines with higher average settlement days (tracked in `vw_settlement_sla_by_line_state`).\n\n2. **Claim Denials and Loss Experience:**\n   * *Impact:* Policyholders experiencing claim denials or unexpected unassigned coverage are significantly more likely to cancel or shop around at renewal.\n   * *Indicator:* High denied claim ratios and large loss occurrences.\n\n3. **Premium Rate Adjustments:**\n   * *Impact:* Substantial rate increases at renewal without corresponding expansion in coverage drive price-sensitive policyholders to competitors.\n   * *Indicator:* Year-over-year written premium increases on expiring policies (`vw_premiums_enriched`).\n\n4. **Broker / Distribution Service Disruption:**\n   * *Impact:* Operational friction or service breakdowns at the broker/underwriter level can trigger churn across an entire portfolio.\n\n---\n\n### Recommended Next Steps to Identify At-Risk Policies\n\nTo proactively identify and retain high-risk policyholders this quarter, consider:\n* **SLA Cross-Referencing:** Querying policies expiring in the next 90 days that have open or recently settled claims with above-average settlement days.\n* **Predictive Churn Model Integration:** Deploying a machine-learning scoring pipeline to output a `ChurnProbabilityScore` table in the Databricks `curated_gold` schema for automated daily monitoring.	2026-08-24 17:11:32.565283+05:30	{"rows": [["Issued", "462726"], ["Cancelled", "63589"], ["Reinstated", "33901"], ["Renewed", "75991"]], "columns": ["EventType", "EventCount"]}
ce54897b-2390-479b-9beb-ad82ab270c61	521dc8ca-3027-46c4-b6c1-30d6fb7b68aa	user	What is our average settlement time this quarter?	2026-08-24 17:15:54.404119+05:30	\N
d3d0f04a-0bad-46aa-aea1-3812a4919013	521dc8ca-3027-46c4-b6c1-30d6fb7b68aa	assistant	Based on the claims data in our Databricks data warehouse, the most recent quarter on record is **Q2 2026**.\n\nFor **Q2 2026**, our average settlement time is **60.35 days** across **24,890 settled claims**.\n\n### Recent Quarter Trend\n\n| Year | Quarter | Average Settlement Time (Days) | Settled Claim Count |\n| :--- | :--- | :--- | :--- |\n| **2026** | **Q2** | **60.35** | **24,890** |\n| 2026 | Q1 | 54.92 | 30,723 |\n| 2025 | Q4 | 110.62 | 19,352 |\n| 2025 | Q3 | 110.30 | 19,739 |\n| 2025 | Q2 | 108.81 | 19,281 |	2026-08-24 17:15:54.441191+05:30	{"rows": [["2026", "2", "60.35423865006027", "24890"], ["2026", "1", "54.921752433030626", "30723"], ["2025", "4", "110.61668044646548", "19352"], ["2025", "3", "110.29793809210193", "19739"], ["2025", "2", "108.81318396348738", "19281"]], "columns": ["YearNum", "QuarterNum", "AvgSettlementDays", "SettledClaimCount"]}
2f87c30b-24dd-418e-99f1-967935a349c2	54adadb0-0beb-41bc-9631-bd743b20e5a6	user	"Which product lines have the highest loss ratios and lowest profitability this year?"	2026-08-24 17:19:09.876982+05:30	\N
1539aa62-c021-4497-a219-8b528537d7ce	54adadb0-0beb-41bc-9631-bd743b20e5a6	assistant	Based on the latest data for **2026** from `poc_alliedworld.curated_gold.vw_broker_loss_ratio`, here is the breakdown of product lines ordered by their loss ratio (from highest loss ratio / lowest profitability to lowest loss ratio):\n\n### Loss Ratio & Claims Summary by Product Line (2026)\n\n| Product Line | Total Paid Claims | Total Premium | Loss Ratio (%) |\n| :--- | :--- | :--- | :--- |\n| **Motor** | $1,948,977,755.38 | $3,815.63 | 51,078,823.95% |\n| **Casualty** | $1,199,614,279.00 | $2,876.36 | 41,706,044.76% |\n| **Property** | $1,323,713,528.63 | $4,806.00 | 27,542,961.15% |\n| **Marine** | $261,313,120.54 | $1,817.10 | 14,380,767.90% |\n| **Energy** | $131,354,590.15 | $1,492.37 | 8,801,764.86% |\n\n---\n\n### Key Takeaways\n\n* **Highest Loss Ratio / Lowest Profitability:** **Motor** has the highest loss ratio and largest total paid claims ($1.95B), making it the least profitable product line this year.\n* **Second Least Profitable:** **Casualty** ranks second highest in loss ratio with ~$1.20B in paid claims.\n* **Most Profitable Relative to Others:** **Energy** has the lowest loss ratio among all lines with $131.35M in paid claims.	2026-08-24 17:19:09.907292+05:30	{"rows": [["Motor", "2026", "1948977755.38", "3815.6277", "51078823.95"], ["Casualty", "2026", "1199614279.00", "2876.3559", "41706044.76"], ["Property", "2026", "1323713528.63", "4805.9957", "27542961.15"], ["Marine", "2026", "261313120.54", "1817.1013", "14380767.90"], ["Energy", "2026", "131354590.15", "1492.3665", "8801764.86"]], "columns": ["ProductLineName", "YearNum", "TotalPaidClaims", "TotalPremium", "LossRatioPct"]}
79ade117-cad6-48e1-b5f9-1d2bcb2e1ae4	4b53bf1f-c961-4eea-acc8-d142ac6a28fd	user	Show me loss ratio of all region 	2026-08-25 12:51:25.848327+05:30	\N
4a1e2d25-243a-4fa2-b33b-89c207644b43	4b53bf1f-c961-4eea-acc8-d142ac6a28fd	assistant	Here is the loss ratio analysis by region based on the company's canonical broker loss ratio data (`poc_alliedworld.curated_gold.vw_broker_loss_ratio`):\n\n### Loss Ratio by Region (Paid Basis)\n\n| Region | Total Paid Claims | Total Premium | Loss Ratio (%) |\n| :--- | :--- | :--- | :--- |\n| **Midwest** | $6,038,645,716.32 | $73,290.11 | 8,239,373.38% |\n| **South** | $7,309,612,002.02 | $88,927.48 | 8,219,744.71% |\n| **Northeast** | $4,508,192,226.48 | $54,970.05 | 8,201,179.22% |\n| **West** | $6,013,083,003.23 | $73,557.44 | 8,174,677.03% |\n\n---\n\n### Key Takeaways\n- **South** represents the highest volume of total paid claims ($7.31B).\n- **Midwest** exhibits the highest aggregate paid loss ratio across all recorded years and product lines.\n- Across all regions, the paid loss ratio remains consistently high relative to earned/written broker premiums recorded in this dataset.\n\n*Data source: `poc_alliedworld.curated_gold.vw_broker_loss_ratio` (Real company data)*	2026-08-25 12:51:25.873329+05:30	{"rows": [["Midwest", "6038645716.32", "73290.1088", "8239373.38"], ["South", "7309612002.02", "88927.4821", "8219744.71"], ["Northeast", "4508192226.48", "54970.0489", "8201179.22"], ["West", "6013083003.23", "73557.4382", "8174677.03"]], "columns": ["RegionName", "TotalPaid", "TotalPremium", "LossRatioPct"]}
37bfbb9e-f4eb-4a23-b5ee-bb6db34b1e79	04ebdbd0-92ac-41e3-91f1-efd1d74cbe20	user	What is the projected revenue for the next quarter, and which regions contribute the most?	2026-08-25 12:57:21.503416+05:30	\N
7c5836d9-8c6e-46c0-9153-617ac2670754	04ebdbd0-92ac-41e3-91f1-efd1d74cbe20	assistant	### 1. Historical Data Summary (Actual Facts)\n\nBased on actual company records in `poc_alliedworld.curated_gold.vw_premiums_enriched`, full quarterly earned and written premium revenues have shown highly stable performance. \n\nFor **Q4 2025** (the most recent complete quarter), total Earned Premium was **$378,018,225.42** ($397,907,220.36 in Written Premium).\n\n#### Regional Contribution Breakdown (Q4 2025 Actuals)\n\n| Region | Earned Premium | Written Premium | Share of Total (Earned) |\n| :--- | :--- | :--- | :--- |\n| **South** | $115,659,189.86 | $121,744,256.72 | 30.6% |\n| **West** | $95,643,147.53 | $100,672,748.81 | 25.3% |\n| **Midwest** | $95,175,432.43 | $100,184,754.58 | 25.2% |\n| **Northeast** | $71,540,455.60 | $75,305,460.25 | 18.9% |\n| **Total** | **$378,018,225.42** | **$397,907,220.36** | **100.0%** |\n\n* **Top Contributor:** The **South** region consistently generates the highest share of revenue (~30.6%).\n* **Secondary Contributors:** The **West** (~25.3%) and **Midwest** (~25.2%) contribute nearly identical secondary shares.\n* **Lowest Contributor:** The **Northeast** region contributes ~18.9% of total earned premium.\n\n---\n\n### 2. Projected Revenue for Next Quarter (*AI projection, not verified against actual data*)\n\n> **Note:** The following figures are AI-generated extrapolations based on historical run-rate trends and do not reflect finalized corporate accounting forecasts.\n\nAssuming steady quarter-over-quarter demand and retention rates aligned with historical baseline levels:\n\n* **Projected Total Earned Premium:** **~$378.0M – $382.0M**\n* **Projected Total Written Premium:** **~$398.0M – $402.0M**\n\n#### Projected Contribution by Region (*AI Projection*)\n\n* **South:** ~$115.5M – $116.5M (~30.6%)\n* **West:** ~$95.5M – $96.5M (~25.3%)\n* **Midwest:** ~$95.0M – $96.0M (~25.2%)\n* **Northeast:** ~$71.0M – $72.0M (~18.9%)	2026-08-25 12:57:21.523819+05:30	{"rows": [["South", "2026", "1", "38605098.73", "40639424.91"], ["West", "2026", "1", "32017054.10", "33706284.19"], ["Midwest", "2026", "1", "31790231.56", "33464058.57"], ["Northeast", "2026", "1", "23908282.64", "25163668.46"], ["South", "2025", "4", "115659189.86", "121744256.72"], ["West", "2025", "4", "95643147.53", "100672748.81"], ["Midwest", "2025", "4", "95175432.43", "100184754.58"], ["Northeast", "2025", "4", "71540455.60", "75305460.25"], ["South", "2025", "3", "115798769.42", "121895408.65"], ["West", "2025", "3", "95849110.58", "100887972.28"], ["Midwest", "2025", "3", "95705177.99", "100747042.18"], ["Northeast", "2025", "3", "71624428.25", "75397864.36"], ["South", "2025", "2", "115825009.04", "121915228.02"], ["West", "2025", "2", "95643598.67", "100684391.98"], ["Midwest", "2025", "2", "95278344.40", "100289371.83"], ["Northeast", "2025", "2", "71397442.44", "75151933.70"], ["South", "2025", "1", "115822037.22", "121926336.55"], ["West", "2025", "1", "95686356.91", "100725461.46"], ["Midwest", "2025", "1", "95416643.37", "100440272.54"], ["Northeast", "2025", "1", "71403716.44", "75161820.62"]], "columns": ["RegionName", "PremiumYear", "PremiumQuarter", "TotalEarnedPremium", "TotalWrittenPremium"]}
2986b75a-b6c3-4b5a-aff7-cd7637c29798	ab75dd4f-baa4-43c0-815d-e283f2a51781	user	Which customers are at high risk of churn this quarter, and what are the top factors contributing to the risk?	2026-08-25 13:06:17.462703+05:30	\N
bf5f2024-e215-4919-ac8a-6276d465fc62	ab75dd4f-baa4-43c0-815d-e283f2a51781	assistant	**Data Availability Note:** ABC Insurance's data warehouse (`poc_alliedworld.curated_gold`) does not currently contain explicit customer/policyholder churn scores or predictive churn risk models in its database tables. \n\nBelow is an **analytical framework** outlining the top indicators and risk factors that typically drive churn, along with how they can be evaluated using existing warehouse data.\n\n---\n\n### Key Factors Contributing to Churn Risk\n\n1. **Unfavorable Claims Experience & Service Delays**\n   * **Indicator:** Long settlement times, high proportion of denied claims, or unresolved claim disputes.\n   * **Impact:** Policyholders who experience friction during the claims process have significantly higher non-renewal rates.\n   * **Data Tracked:** Claim settlement SLAs (`vw_settlement_sla_by_line_state`) and claim status distributions (`insurance_analytics`).\n\n2. **Upcoming Expirations without Renewal Engagement**\n   * **Indicator:** Policies set to expire within the current quarter that have not logged lifecycle renewal events or broker interaction.\n   * **Impact:** Unattended policy renewals often result in lost accounts to competing carriers.\n   * **Data Tracked:** Policy effective/expiry dates (`dimpolicy`) and lifecycle events (`factpolicylifecycle`).\n\n3. **Significant Rate / Premium Adjustments**\n   * **Indicator:** Sharp year-over-year increases in written premium without accompanying expanded coverage.\n   * **Impact:** Rate spikes prompt brokers and policyholders to re-shop coverage in the open market.\n   * **Data Tracked:** Premium records (`factpremiums`, `vw_premiums_enriched`).\n\n4. **Service & Utilization Drop-Off (Health/Patient Accounts)**\n   * **Indicator:** A surge in appointment cancellations or a sharp drop in facility/provider visits prior to renewal.\n   * **Impact:** Reduced engagement often signals that a patient or insured party is switching networks or service providers.\n   * **Data Tracked:** Cancelled appointments (`cancelled_appointments`) and patient visit summaries (`patient_summary`).\n\n---\n\n### Recommended Next Steps to Enable Churn Analytics\n* **Predictive Churn Scoring:** Integrate a machine learning model that joins `dimpolicy` (expiry dates), `vw_claims_enriched` (claims friction), and `vw_premiums_enriched` (premium changes) to assign a probability score to each account.\n* **Proactive Renewal Queue:** Filter policies expiring in the next 30–90 days with recent loss history or high settlement SLA days for proactive outreach by underwriting and broker teams.	2026-08-25 13:06:17.478365+05:30	\N
0c3ab718-030a-4fa3-9c7e-0752459fa87b	f1d69642-7515-405b-a1a3-8db7981c8b8e	user	Show me the loss ratio trend by region for this year	2026-08-25 13:07:05.670335+05:30	\N
c460a5b0-9d42-444f-941a-7212ebabf70d	f1d69642-7515-405b-a1a3-8db7981c8b8e	assistant	Here is the loss ratio breakdown by region for the current year (**2026**), based on the company's data warehouse records.\n\n---\n\n### 1. Quarterly Loss Ratio Trend (Incurred / Earned Basis) — 2026\n\nThe table below shows the quarterly incurred loss, earned premium, and resulting loss ratio by region for **2026** (from `vw_loss_ratio_by_coverage_region_quarter`):\n\n| Region | Quarter | Total Incurred Loss ($) | Total Earned Premium ($) | Loss Ratio (%) |\n| :--- | :---: | :--- | :--- | :---: |\n| **West** | Q1 | $1,360,291,520.18 | $32,017,054.10 | **4,248.65%** |\n| **Midwest** | Q1 | $1,326,778,405.28 | $31,790,231.56 | **4,173.54%** |\n| **Northeast** | Q1 | $986,836,617.96 | $23,908,282.64 | **4,127.59%** |\n| **South** | Q1 | $1,592,123,660.57 | $38,605,098.73 | **4,124.13%** |\n| **South** | Q2 | $871,872,017.33 | *Pending / Incomplete* | — |\n| **Midwest** | Q2 | $714,157,519.62 | *Pending / Incomplete* | — |\n| **West** | Q2 | $711,711,039.00 | *Pending / Incomplete* | — |\n| **Northeast** | Q2 | $551,710,685.14 | *Pending / Incomplete* | — |\n\n*Note: Earned premiums for Q2 2026 have not yet fully posted/earned, so loss ratios for Q2 are pending.*\n\n---\n\n### 2. Year-to-Date Paid-Basis Summary — 2026\n\nBelow is the standard paid-basis summary by region for **2026** (from `vw_broker_loss_ratio`):\n\n| Region | Total Paid Loss ($) | Written Premium ($) | Paid Loss Ratio (%) |\n| :--- | :--- | :--- | :---: |\n| **West** | $1,240,587,782.22 | $3,764.17 | **32,957,844.58%** |\n| **Midwest** | $1,224,248,075.42 | $3,714.34 | **32,960,015.88%** |\n| **Northeast** | $921,880,019.77 | $2,808.76 | **32,821,545.61%** |\n| **South** | $1,478,257,396.29 | $4,520.17 | **32,703,552.16%** |\n\n---\n\n### Key Takeaways\n* **Regional Distribution**: The **South** region accounts for the highest volume of total incurred and paid losses ($1.59B in Q1 incurred loss), followed by **West** and **Midwest**.\n* **Performance Consistency**: Loss ratios across regions in Q1 2026 are relatively uniform, ranging between **4,124%** (South) and **4,248%** (West).	2026-08-25 13:07:05.697583+05:30	{"rows": [["Midwest", "2026", "1224248075.42", "3714.3431", "32960015.88"], ["Northeast", "2026", "921880019.77", "2808.7648", "32821545.61"], ["South", "2026", "1478257396.29", "4520.1738", "32703552.16"], ["West", "2026", "1240587782.22", "3764.1654", "32957844.58"]], "columns": ["RegionName", "YearNum", "TotalPaid", "TotalPremium", "LossRatioPct"]}
50170a64-1065-4461-9624-42a9b2110bf7	d7025717-02cd-4c1b-a105-9276e96e7cb1	user	"Which product lines have the highest loss ratios and lowest profitability this year?"	2026-08-26 00:13:57.851948+05:30	\N
d78341ac-89c7-445e-afca-09cd8ea2c05f	d7025717-02cd-4c1b-a105-9276e96e7cb1	assistant	Based on company data for the current year in our records (**2026**), here is the loss ratio and profitability breakdown by product line, ordered from the highest loss ratio (lowest profitability) to the lowest:\n\n### **Loss Ratio & Profitability by Product Line (2026)**\n\n| Product Line | Total Premium | Total Paid Claims | Loss Ratio (%) | Estimated Profit / (Loss) |\n| :--- | :--- | :--- | :--- | :--- |\n| **Motor** | $3,815.63 | $1,948,977,755.38 | 51,078,823.95% | -$1,948,973,939.75 |\n| **Casualty** | $2,876.36 | $1,199,614,279.00 | 41,706,044.76% | -$1,199,611,402.64 |\n| **Property** | $4,805.00 | $1,323,713,528.63 | 27,542,961.15% | -$1,323,708,722.63 |\n| **Marine** | $1,817.10 | $261,313,120.54 | 14,380,767.90% | -$261,311,303.44 |\n| **Energy** | $1,492.37 | $131,354,590.15 | 8,801,764.86% | -$131,353,097.78 |\n\n---\n\n### **Key Takeaways (Verified Company Data)**\n* **Highest Loss Ratio & Lowest Profitability:** **Motor** has the highest loss ratio and the largest underwriting deficit ($1.95B loss), followed closely by **Casualty** ($1.20B loss) and **Property** ($1.32B loss).\n* **Overall Trend:** All five product lines show extreme loss ratios for 2026 due to minimal written/earned premium recorded relative to historical claim payouts in this reporting period.\n\n*(Note: Figures are pulled directly from `poc_alliedworld.curated_gold.vw_broker_loss_ratio` for the latest recorded year, 2026).*	2026-08-26 00:13:57.89454+05:30	{"rows": [["Motor", "2026", "1948977755.38", "3815.6277", "51078823.95", "-1948973939.7523"], ["Casualty", "2026", "1199614279.00", "2876.3559", "41706044.76", "-1199611402.6441"], ["Property", "2026", "1323713528.63", "4805.9957", "27542961.15", "-1323708722.6343"], ["Marine", "2026", "261313120.54", "1817.1013", "14380767.90", "-261311303.4387"], ["Energy", "2026", "131354590.15", "1492.3665", "8801764.86", "-131353097.7835"]], "columns": ["ProductLineName", "YearNum", "TotalPaid", "TotalPremium", "LossRatioPct", "EstimatedUnderwritingProfit"]}
b9a1ef60-b71b-4d64-82f4-4729372a5bda	c1d50da2-c573-44e8-bf97-708026c54acf	user	Show me the loss ratio trend by region for this year	2026-08-31 14:20:12.251055+05:30	\N
7750d505-08d5-464e-8f47-db9bef8be6ab	16a64e22-63b0-49f7-921d-a30d4403ec44	user	Are there any unusual claims this month?	2026-08-31 14:20:18.617895+05:30	\N
14aeeceb-6a66-4fb0-8fab-c10d4f34b07d	d42b3003-3bb3-4686-ada3-8de9567b107e	user	Show me the loss ratio trend by region for this year	2026-08-31 14:21:11.529774+05:30	\N
6ea178bf-079d-4a84-8149-7e09bd6a9db6	eedbac44-1d41-4aef-9e94-bea86ddf2eb3	user	Show me the loss ratio trend by region for this year	2026-09-01 21:45:24.96383+05:30	\N
1d4bc3c7-7487-4e5a-9724-500a3414ae57	eedbac44-1d41-4aef-9e94-bea86ddf2eb3	assistant	### Data Availability Notice\nI do not have access to Vantage Insurance's live internal database or real-time claims and premium data. To view your actual loss ratio trend by region for this year, access to live company reporting tools or databases is required.\n\n---\n\n### Category 3: General Knowledge & Industry Context\nIn property and casualty (P&C) insurance, the **loss ratio** is calculated as:\n\n$$\\text{Loss Ratio} = \\frac{\\text{Incurred Losses} + \\text{Loss Adjustment Expenses}}{\\text{Net Earned Premiums}}$$\n\nA combined target for underwriting profitability generally requires a loss ratio below 60%–65%, depending on the expense ratio. Industry-wide trends impacting regional loss ratios this year include:\n\n* **Catastrophe Exposure:** Regions subject to severe convective storms, hurricanes, or wildfires experience significant volatility in property loss ratios.\n* **Inflationary Pressures:** Rising costs for auto parts, labor, and building materials have driven up severity across personal and commercial lines globally.\n* **Reinsurance Costs:** Higher primary insurance loss ratios in high-hazard regions are driving rate increases across commercial property portfolios.\n\n---\n\n### Category 2: AI Projection Benchmark (Not verified against actual company data)\nThe table below represents an **AI benchmark projection based on broader market dynamics**, provided strictly as an example framework. It does **not** reflect real figures from Vantage Insurance.\n\n| Region | Projected Loss Ratio (YTD) | Trend vs. Prior Year | Primary Market Driver |\n| :--- | :--- | :--- | :--- |\n| **North America - East** | 68.5% | +3.2% | Severe convective storms and high property repair costs |\n| **North America - West** | 62.0% | -1.5% | Improved wildfire mitigation and rate adjustments |\n| **North America - Central** | 71.4% | +4.1% | High hail and windstorm frequency impacting personal lines |\n| **EMEA** | 59.3% | -0.8% | Stable catastrophe year and strong commercial property pricing |\n| **APAC** | 61.5% | +1.0% | Supply chain disruption impacting auto claims severity |\n| **Latin America** | 64.8% | +0.5% | General inflation impacting motor and liability lines |\n\n*(Label: AI projection, not verified against actual company data.)*	2026-09-01 21:45:25.013458+05:30	\N
\.


--
-- Data for Name: data_source_connections; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.data_source_connections (id, tenant_id, platform, config, secret_ref, is_active, created_at) FROM stdin;
7e9045fd-7a95-4254-925c-a4e6a56ba84b	11111111-1111-1111-1111-111111111111	databricks	{"host": "dbc-ef772806-308c.cloud.databricks.com", "schema": "curated_gold", "catalog": "poc_alliedworld", "warehouse_id": "ec94e5287125e125", "genie_space_id": "01f0baaeb8c215c4ba992f3d177bd339"}	DATABRICKS_PAT	t	2026-08-13 19:11:29.956335+05:30
\.


--
-- Data for Name: genie_query_parameter_fields; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.genie_query_parameter_fields (id, tenant_id, user_id, field_name, options, display_order, created_at) FROM stdin;
\.


--
-- Data for Name: genie_question_templates; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.genie_question_templates (id, tenant_id, user_id, template) FROM stdin;
\.


--
-- Data for Name: genie_suggested_questions; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.genie_suggested_questions (id, tenant_id, user_id, question_text, display_order, created_at) FROM stdin;
\.


--
-- Data for Name: governance_reviews; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.governance_reviews (id, tenant_id, user_id, question, check_type, reason, status, reviewed_by, reviewed_at, decision_note, created_at) FROM stdin;
\.


--
-- Data for Name: local_secrets; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.local_secrets (secret_ref, ciphertext, created_at, updated_at) FROM stdin;
local:llm-api-key:2a656728-724b-497c-b848-bd438b4a9448	gAAAAABqlUB2d1--_3TSjZ0fQ2fdI9umnuqlAioYAdArHzdvTaHOT8GIS1I9jdwjLtDzAVDnftqSsCnrSFFg9l_hgQwXA6NVCvpoBueP4bhpIdJYGnC1N3Vj7gm5sV0iAYJXxPpevfvFypKPO1BSlyrmoO1TsbWCOw==	2026-08-31 14:21:02.302873+05:30	2026-08-31 14:21:02.302873+05:30
local:databricks-pat:bc63ce30-b20d-404d-a2a4-afd6ccf36f4c	gAAAAABqkXu_RsQtaJ7CIuwbKH_9DfyB6aPlDbydmCzVWOGwrbx0l3nfSmcDt5X_w2Nge-Mg807QoVVbPGkP_YwctF2P3YObaUzWv2GXhBuAMzn9b_dkAM_mJPFqr1fVkCTQV1HhNyfx	2026-08-28 17:44:55.197422+05:30	2026-08-28 17:44:55.197422+05:30
local:llm-api-key:051ef49b-3fe1-41aa-82cf-cfd859fb8ef4	gAAAAABqkXu_IgyyEfWb5zXUiyvLRp00uMAPBqljuWCPtzZh6GWPMUYK3GUjaZa4-TLI_NIwANtACh7Te8r0clcc7a9y_G2UUGOYDrORfS1jTgsugzftwNC-pVRQid3v312TTLMhAUwhKsnkiWDugVVDKjVNzC2IsQ==	2026-08-28 17:44:55.264103+05:30	2026-08-28 17:44:55.264103+05:30
\.


--
-- Data for Name: pinned_items; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.pinned_items (id, tenant_id, user_id, source, item_type, title, payload, created_at) FROM stdin;
1d9bdc96-2c04-4418-9055-1207716f252c	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	ask_ai	chart	"Which product lines have the highest loss ratios and lowest profitability this…	{"rows": [["Motor", "2026", "1948977755.38", "3815.6277", "51078823.95", "-1948973939.7523"], ["Casualty", "2026", "1199614279.00", "2876.3559", "41706044.76", "-1199611402.6441"], ["Property", "2026", "1323713528.63", "4805.9957", "27542961.15", "-1323708722.6343"], ["Marine", "2026", "261313120.54", "1817.1013", "14380767.90", "-261311303.4387"], ["Energy", "2026", "131354590.15", "1492.3665", "8801764.86", "-131353097.7835"]], "columns": ["ProductLineName", "YearNum", "TotalPaid", "TotalPremium", "LossRatioPct", "EstimatedUnderwritingProfit"]}	2026-08-26 00:30:06.70167+05:30
\.


--
-- Data for Name: schema_annotations; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.schema_annotations (id, tenant_id, catalog_name, schema_name, table_name, column_name, note, created_by, created_at) FROM stdin;
d010abf0-e40b-45e5-9a10-8083be61802a	11111111-1111-1111-1111-111111111111	poc_alliedworld	curated_gold	vw_broker_loss_ratio	\N	Canonical PAID-basis loss ratio by product line and year. Use this for standard loss ratio questions.	b1111111-0000-0000-0000-000000000001	2026-08-19 02:00:54.65073+05:30
39f2956d-3a6e-4c6f-8d44-b9a55c63e145	11111111-1111-1111-1111-111111111111	poc_alliedworld	curated_gold	vw_broker_quarterly_kpis	\N	Actuarial INCURRED/EARNED basis loss ratio — a different methodology than vw_broker_loss_ratio. Only use this table if the question explicitly asks for incurred or actuarial loss ratio.	b1111111-0000-0000-0000-000000000001	2026-08-19 02:03:04.573354+05:30
\.


--
-- Data for Name: use_cases; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.use_cases (id, tenant_id, title, description, category, sample_question, icon_key, created_at, generated_sql) FROM stdin;
ea056754-b073-48e9-a3e8-cd629d5bbc74	11111111-1111-1111-1111-111111111111	Loss ratio trend	Compare loss ratio across regions and product lines.	Claims	Show me the loss ratio trend by region for this year	trending-up	2026-08-16 01:53:30.815765+05:30	\N
9f9536fc-5439-463f-8296-b8d4fbc05df7	11111111-1111-1111-1111-111111111111	Anomaly detection	Find unusual claims before they become material issues.	Claims	Are there any unusual claims this month?	scan-search	2026-08-16 01:53:30.815765+05:30	\N
\.


--
-- Data for Name: user_credentials; Type: TABLE DATA; Schema: tenant_11111111111111111111111111111111; Owner: -
--

COPY tenant_11111111111111111111111111111111.user_credentials (id, tenant_id, user_id, databricks_host, databricks_warehouse_id, databricks_genie_space_id, databricks_catalog, databricks_schema, databricks_pat_secret_ref, llm_provider, llm_api_key_secret_ref, last_validated_at, last_validation_ok, created_at, updated_at) FROM stdin;
72c6f094-96d1-4453-b7cb-f4d7d09a988d	11111111-1111-1111-1111-111111111111	b1111111-0000-0000-0000-000000000001	dbc-ef772806-308c.cloud.databricks.com	ec94e5287125e125	01f0baaeb8c215c4ba992f3d177bd339	\N	\N	local:databricks-pat:bc63ce30-b20d-404d-a2a4-afd6ccf36f4c	gemini	local:llm-api-key:2a656728-724b-497c-b848-bd438b4a9448	\N	\N	2026-08-28 17:16:40.440074+05:30	2026-08-31 14:21:02.338603+05:30
\.


--
-- Name: chat_conversations chat_conversations_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.chat_conversations
    ADD CONSTRAINT chat_conversations_pkey PRIMARY KEY (id);


--
-- Name: chat_messages chat_messages_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.chat_messages
    ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id);


--
-- Name: data_source_connections data_source_connections_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.data_source_connections
    ADD CONSTRAINT data_source_connections_pkey PRIMARY KEY (id);


--
-- Name: genie_query_parameter_fields genie_query_parameter_fields_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.genie_query_parameter_fields
    ADD CONSTRAINT genie_query_parameter_fields_pkey PRIMARY KEY (id);


--
-- Name: genie_question_templates genie_question_templates_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.genie_question_templates
    ADD CONSTRAINT genie_question_templates_pkey PRIMARY KEY (id);


--
-- Name: genie_suggested_questions genie_suggested_questions_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.genie_suggested_questions
    ADD CONSTRAINT genie_suggested_questions_pkey PRIMARY KEY (id);


--
-- Name: governance_reviews governance_reviews_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.governance_reviews
    ADD CONSTRAINT governance_reviews_pkey PRIMARY KEY (id);


--
-- Name: local_secrets local_secrets_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.local_secrets
    ADD CONSTRAINT local_secrets_pkey PRIMARY KEY (secret_ref);


--
-- Name: pinned_items pinned_items_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.pinned_items
    ADD CONSTRAINT pinned_items_pkey PRIMARY KEY (id);


--
-- Name: schema_annotations schema_annotations_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.schema_annotations
    ADD CONSTRAINT schema_annotations_pkey PRIMARY KEY (id);


--
-- Name: use_cases use_cases_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.use_cases
    ADD CONSTRAINT use_cases_pkey PRIMARY KEY (id);


--
-- Name: user_credentials user_credentials_pkey; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.user_credentials
    ADD CONSTRAINT user_credentials_pkey PRIMARY KEY (id);


--
-- Name: user_credentials user_credentials_user_id_key; Type: CONSTRAINT; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE ONLY tenant_11111111111111111111111111111111.user_credentials
    ADD CONSTRAINT user_credentials_user_id_key UNIQUE (user_id);


--
-- Name: genie_question_templates_scope_idx; Type: INDEX; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE UNIQUE INDEX genie_question_templates_scope_idx ON tenant_11111111111111111111111111111111.genie_question_templates USING btree (tenant_id, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid));


--
-- Name: user_credentials_user_id_idx; Type: INDEX; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE INDEX user_credentials_user_id_idx ON tenant_11111111111111111111111111111111.user_credentials USING btree (user_id);


--
-- Name: data_source_connections; Type: ROW SECURITY; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE tenant_11111111111111111111111111111111.data_source_connections ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_query_parameter_fields genie_fields_visible; Type: POLICY; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE POLICY genie_fields_visible ON tenant_11111111111111111111111111111111.genie_query_parameter_fields USING (((tenant_id = public.current_tenant_id_safe()) AND ((user_id = public.current_user_id_safe()) OR (user_id IS NULL))));


--
-- Name: genie_query_parameter_fields; Type: ROW SECURITY; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE tenant_11111111111111111111111111111111.genie_query_parameter_fields ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_question_templates; Type: ROW SECURITY; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE tenant_11111111111111111111111111111111.genie_question_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_suggested_questions; Type: ROW SECURITY; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE tenant_11111111111111111111111111111111.genie_suggested_questions ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_suggested_questions genie_suggestions_visible; Type: POLICY; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE POLICY genie_suggestions_visible ON tenant_11111111111111111111111111111111.genie_suggested_questions USING (((tenant_id = public.current_tenant_id_safe()) AND ((user_id = public.current_user_id_safe()) OR (user_id IS NULL))));


--
-- Name: genie_question_templates genie_template_visible; Type: POLICY; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE POLICY genie_template_visible ON tenant_11111111111111111111111111111111.genie_question_templates USING (((tenant_id = public.current_tenant_id_safe()) AND ((user_id = public.current_user_id_safe()) OR (user_id IS NULL))));


--
-- Name: data_source_connections query_parameters_visible; Type: POLICY; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE POLICY query_parameters_visible ON tenant_11111111111111111111111111111111.data_source_connections USING ((tenant_id = public.current_tenant_id_safe()));


--
-- Name: user_credentials; Type: ROW SECURITY; Schema: tenant_11111111111111111111111111111111; Owner: -
--

ALTER TABLE tenant_11111111111111111111111111111111.user_credentials ENABLE ROW LEVEL SECURITY;

--
-- Name: user_credentials user_owns_credentials; Type: POLICY; Schema: tenant_11111111111111111111111111111111; Owner: -
--

CREATE POLICY user_owns_credentials ON tenant_11111111111111111111111111111111.user_credentials USING (((tenant_id = public.current_tenant_id_safe()) AND (user_id = public.current_user_id_safe())));


--
-- PostgreSQL database dump complete
--

\unrestrict 3TE4Q8WozSMU0DQS5MBkp76LOYRW0LGa7B7G5drm2Fl11KEhlU0xL5l5GJwiQyZ

