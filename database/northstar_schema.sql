--
-- PostgreSQL database dump
--

\restrict VZmBCMGB5jheUkP0zRjp2lreDRMdsZgJlmpDFc9SERcF0ubPzkHl6Djryk8VKat

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
-- Name: tenant_22222222222222222222222222222222; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA tenant_22222222222222222222222222222222;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: chat_conversations; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.chat_conversations (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    title text DEFAULT 'New conversation'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_messages; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.chat_messages (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    conversation_id uuid NOT NULL,
    role text NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    chart_data jsonb
);


--
-- Name: data_source_connections; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.data_source_connections (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    platform text NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    secret_ref text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: genie_query_parameter_fields; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.genie_query_parameter_fields (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid,
    field_name text NOT NULL,
    options text[] NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: genie_question_templates; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.genie_question_templates (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid,
    template text NOT NULL
);


--
-- Name: genie_suggested_questions; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.genie_suggested_questions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid,
    question_text text NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: governance_reviews; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.governance_reviews (
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
-- Name: local_secrets; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.local_secrets (
    secret_ref text NOT NULL,
    ciphertext text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pinned_items; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.pinned_items (
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
-- Name: schema_annotations; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.schema_annotations (
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
-- Name: use_cases; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.use_cases (
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
-- Name: user_credentials; Type: TABLE; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE TABLE tenant_22222222222222222222222222222222.user_credentials (
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
-- Data for Name: chat_conversations; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.chat_conversations (id, tenant_id, user_id, title, created_at, updated_at) FROM stdin;
aab04027-c3e8-4711-afa5-01663cb1e369	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000003	Show me the delinquency aging buckets by product for the las…	2026-08-26 14:44:49.231586+05:30	2026-08-26 14:44:53.852359+05:30
775d15b7-e992-4a6c-b618-002710574901	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000005	What is our current delinquency rate and NPL ratio by produc…	2026-08-26 15:24:16.436603+05:30	2026-08-26 15:24:16.460847+05:30
46409a7c-ff75-4f7a-a680-f6c6cb577ff8	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000001	New conversation	2026-08-16 02:07:35.867556+05:30	2026-08-26 01:14:04.969638+05:30
f56ea1d5-fc3b-4d1b-bb7c-4130523e9e06	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000001	What is our current delinquency rate and NPL ratio by produc…	2026-08-26 02:22:16.945023+05:30	2026-08-26 02:33:09.522756+05:30
5bd35c9b-a358-48a8-84b8-2a22333ac4eb	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000005	What is our current delinquency rate and NPL ratio by produc…	2026-08-26 12:17:12.863126+05:30	2026-08-26 12:17:12.872445+05:30
308319c1-c4e6-4039-96df-fdae70d53992	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000001	What is our current delinquency rate and NPL ratio by produc…	2026-08-26 12:29:01.501028+05:30	2026-08-26 12:29:01.513397+05:30
61a03e82-2b0f-4bda-a2e2-dc401ccc7220	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000005	Which products or regions have the highest loss ratios this …	2026-08-26 12:44:39.61422+05:30	2026-08-26 12:44:39.623769+05:30
11002dd0-f2a5-4826-a7a3-9371f8229aeb	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000005	What is our current delinquency rate and NPL ratio by produc…	2026-08-26 12:52:10.994088+05:30	2026-08-26 12:52:15.612011+05:30
d0421b38-1ebd-4ae8-b2c3-4c2632bcf0cc	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000005	Show me the delinquency aging buckets by product for the las…	2026-08-26 12:53:09.815404+05:30	2026-08-26 12:53:09.828468+05:30
6a628262-ac52-4c4e-b885-892fa4d6ffbe	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000001	What is our current delinquency rate and NPL ratio by produc…	2026-08-28 17:02:08.975012+05:30	2026-08-28 17:02:22.008334+05:30
ff7a80e5-5924-4690-8c90-fb1baec24609	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000001	Show me the delinquency aging buckets by product for the las…	2026-08-29 12:34:13.679215+05:30	2026-08-29 12:34:13.683183+05:30
98a153c6-22e8-4fef-b02a-ead6bcc0dffc	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000001	What is our current delinquency rate and NPL ratio by produc…	2026-08-29 12:34:18.107268+05:30	2026-08-29 12:34:18.116368+05:30
a636a2d8-d1c8-4111-84d3-e268fe827d05	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000001	What is our current delinquency rate and NPL ratio by produc…	2026-08-29 12:49:29.709864+05:30	2026-08-29 12:49:29.74725+05:30
1ac4441c-7a9a-462e-8312-4bd81d0cab49	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000001	Show transactions flagged as suspicious in the last 24 hours…	2026-08-29 13:03:08.297866+05:30	2026-08-29 13:03:08.315205+05:30
a526f69a-46b9-4dcb-89ba-64931f19d7b9	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000001	Show transactions flagged as suspicious in the last 24 hours…	2026-08-29 13:03:43.490999+05:30	2026-08-29 13:03:43.515756+05:30
d6d066ba-329c-4f12-93fd-449bf2aa4253	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000001	What is our current delinquency rate and NPL ratio by produc…	2026-08-28 20:09:34.23931+05:30	2026-08-29 13:05:50.067958+05:30
ab7689ec-239c-46b9-9b3f-d9b0e7a2037e	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000005	Show Loan Count for Auto Loan in Midwest for Retail	2026-09-03 16:26:14.386388+05:30	2026-09-03 16:26:14.396968+05:30
5aa092d1-6744-43c2-aa7f-dafa78b2a39b	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000005	Show Loan Count for Auto Loan in Midwest for Retail	2026-09-03 16:26:50.999757+05:30	2026-09-03 16:26:51.027401+05:30
a577d8df-76a0-44bc-beec-43af753ff7eb	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000005	Show Outstanding Balance for Personal Loan in Northeast for …	2026-09-03 19:11:11.005703+05:30	2026-09-03 19:11:11.021651+05:30
6a0bed81-381a-4149-8a41-e4bc32e73979	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000005	Show Outstanding Balance for Personal Loan in Northeast for …	2026-09-03 19:11:45.163895+05:30	2026-09-03 19:12:03.138187+05:30
\.


--
-- Data for Name: chat_messages; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.chat_messages (id, conversation_id, role, content, created_at, chart_data) FROM stdin;
08385895-8056-4581-bf91-e31a40c0d41c	46409a7c-ff75-4f7a-a680-f6c6cb577ff8	user	Show delinquency rates by loan type this quarter	2026-08-26 00:58:54.750882+05:30	\N
bf9704d5-7290-4fdb-99f9-b58e67eb4dc4	46409a7c-ff75-4f7a-a680-f6c6cb577ff8	assistant	### Data Availability Notice\n\nI do not have access to XYZ Bank’s live database or current quarter financial systems. Therefore, I cannot provide real-time or historical delinquency rates pulled directly from the bank's internal records for this quarter.\n\n---\n\n### 1. Facts Pulled from Real Company Data\n* **Status:** **Unavailable.** Real-time company data for XYZ Bank is required to answer this question accurately. Please connect to the bank's reporting system or database to view the actual figures for the current quarter.\n\n---\n\n### 2. AI Projection / Industry Benchmark (Illustrative Only)\n\n> **Note:** The table below is an **AI projection / illustrative benchmark, not verified against actual XYZ Bank data**.\n\nThe following table provides hypothetical figures based on recent U.S. banking industry averages to illustrate how delinquency rates (typically 30+ days past due) are generally distributed across loan types:\n\n| Loan Type | AI Projected Delinquency Rate (%) | Typical Industry Range (%) |\n| :--- | :--- | :--- |\n| **Credit Cards** | 3.10% | 2.50% – 3.50% |\n| **Auto Loans** | 2.40% | 2.00% – 2.80% |\n| **Personal Unsecured Loans** | 3.60% | 3.00% – 4.20% |\n| **Residential Mortgages** | 1.80% | 1.50% – 2.20% |\n| **Commercial Real Estate (CRE)** | 1.20% | 1.00% – 2.00% |\n| **Commercial & Industrial (C&I)** | 1.10% | 0.90% – 1.50% |\n\n---\n\n### 3. General Knowledge & Context\n\nIn commercial banking, loan delinquency tracking is critical for credit risk management and loss provisioning:\n\n* **Definition of Delinquency:** A loan is generally considered delinquent when a borrower misses a scheduled payment. Financial institutions typically track delinquency in buckets: 30–59 days, 60–89 days, and 90+ days past due.\n* **Key Drivers:**\n  * **Unsecured Consumer Debt (Credit Cards, Personal Loans):** Typically exhibits higher delinquency rates due to the lack of underlying collateral.\n  * **Secured Consumer Debt (Mortgages, Auto):** Generally maintains lower delinquency rates because borrowers risk losing primary assets (homes or vehicles).\n  * **Commercial Lending:** Rates depend heavily on macro trends, interest rate environments, and industry-specific headwinds (e.g., office space trends in Commercial Real Estate).	2026-08-26 00:59:00.518706+05:30	\N
0ac8622d-68c1-4a6c-8adb-dd6056af4222	46409a7c-ff75-4f7a-a680-f6c6cb577ff8	user	Are there any unusual transactions this week?	2026-08-26 01:13:53.519642+05:30	\N
3383034e-4e3e-42d6-9c1a-72971fe45d81	46409a7c-ff75-4f7a-a680-f6c6cb577ff8	assistant	### Data Availability Notice\n\nI do not have access to XYZ Bank’s live transaction monitoring tools, core banking systems, or Anti-Money Laundering (AML) / fraud detection feeds. Therefore, I cannot inspect actual account activity or report real-time transaction flags for this week.\n\n---\n\n### 1. Facts Pulled from Real Company Data\n\n* **Status:** **Unavailable.** Access to live transaction monitoring databases is required to identify actual flagged, blocked, or unusual transactions for this week.\n\n---\n\n### 2. AI Projection / Illustrative Anomaly Profile\n\n> **Note:** The table below is an **AI projection / illustrative risk scenario, not verified against actual XYZ Bank data**.\n\nTo illustrate how unusual transactions are typically flagged and categorized in transaction monitoring analytics, the table below demonstrates a hypothetical weekly summary for a bank of similar scale:\n\n| Flag Category | Illustrative Weekly Volume | Typical Risk Level | Common Indicator / Trigger |\n| :--- | :--- | :--- | :--- |\n| **High-Volume Velocity Spikes** | 45 alerts | Medium | Rapid succession of transactions within minutes |\n| **Unusual International Wires** | 12 alerts | High | Out-of-pattern transfers to high-risk jurisdictions |\n| **Large Cash Structuring** | 8 alerts | High | Consecutive deposits just below reporting thresholds ($10k) |\n| **Out-of-Pattern High Value** | 28 alerts | Medium | Single transaction >5x the account holder's average |\n| **New Device / Geographic Anomaly** | 115 alerts | Low–Medium | Sign-in and transaction from unrecognized IP or location |\n\n---\n\n### 3. General Knowledge & Context\n\nIn transaction analytics and financial crime compliance, an "unusual transaction" is defined as activity that deviates significantly from a customer's established baseline or violates standard regulatory rule sets:\n\n* **Key Anomaly Indicators:**\n  * **Behavioral Shifts:** Sudden changes in transaction frequency, payment types, or counterparties.\n  * **Geographic Discrepancies:** Transactions originating from unfamiliar foreign locations or unexpected IP addresses.\n  * **Threshold Avoidance:** Activity structured specifically to evade mandatory reporting limits (e.g., BSA/AML thresholds).\n* **Detection & Resolution Workflow:**\n  1. **Automated Rule & ML Scoring:** Algorithms analyze incoming transactions in real time and assign risk scores.\n  2. **Alert Generation:** Transactions exceeding risk thresholds are held or flagged for manual review.\n  3. **Compliance Review:** Fraud analysts or AML specialists investigate flagged transactions to confirm legitimacy or escalate for Suspicious Activity Report (SAR) filing.	2026-08-26 01:14:04.969638+05:30	\N
b30d51c0-9f3c-4189-846c-91fe1e49d028	f56ea1d5-fc3b-4d1b-bb7c-4130523e9e06	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-26 02:22:21.600816+05:30	\N
3a41f165-b72f-4604-8723-8869a534aa4d	f56ea1d5-fc3b-4d1b-bb7c-4130523e9e06	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-26 02:30:51.729647+05:30	\N
298792c7-4332-45e9-947b-52316a3965e4	f56ea1d5-fc3b-4d1b-bb7c-4130523e9e06	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-26 02:33:09.522756+05:30	\N
9bc7930d-237e-4450-86c7-f7f8b5e177d4	5bd35c9b-a358-48a8-84b8-2a22333ac4eb	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-26 12:17:12.872445+05:30	\N
df403319-d58e-4bfb-8fbd-bce0eb75f6c1	308319c1-c4e6-4039-96df-fdae70d53992	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-26 12:29:01.513397+05:30	\N
38e324de-cda5-4e08-ad2d-29dfdbf0f706	61a03e82-2b0f-4bda-a2e2-dc401ccc7220	user	Which products or regions have the highest loss ratios this quarter, and what factors are driving the increase?	2026-08-26 12:44:39.623769+05:30	\N
324f118c-5ef1-4575-8f98-ee3d891f115c	11002dd0-f2a5-4826-a7a3-9371f8229aeb	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-26 12:52:15.612011+05:30	\N
1c9527bf-9916-42be-88ed-ad7fce4f35ef	d0421b38-1ebd-4ae8-b2c3-4c2632bcf0cc	user	Show me the delinquency aging buckets by product for the last two quarters	2026-08-26 12:53:09.828468+05:30	\N
7b99bd10-f16d-4525-bf90-faa052180cb4	aab04027-c3e8-4711-afa5-01663cb1e369	user	Show me the delinquency aging buckets by product for the last two quarters	2026-08-26 14:44:53.852359+05:30	\N
3427160d-f8c8-47f4-b617-787d10f4bf88	775d15b7-e992-4a6c-b618-002710574901	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-26 15:24:16.460847+05:30	\N
8e27fdc6-ee93-4bba-b378-50cc467c908c	6a628262-ac52-4c4e-b885-892fa4d6ffbe	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-28 17:02:22.008334+05:30	\N
f41eb050-9e59-4f8f-abca-f34da1bb37dc	d6d066ba-329c-4f12-93fd-449bf2aa4253	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-28 20:09:40.134284+05:30	\N
9e5476e3-fb5d-40c3-8c4d-2cf0371e7e4a	ff7a80e5-5924-4690-8c90-fb1baec24609	user	Show me the delinquency aging buckets by product for the last two quarters	2026-08-29 12:34:13.683183+05:30	\N
235bbbfc-a56a-4eab-a71a-b45e95221c3b	98a153c6-22e8-4fef-b02a-ead6bcc0dffc	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-29 12:34:18.116368+05:30	\N
027f2389-cf35-498b-8f0c-c91791be26fb	a636a2d8-d1c8-4111-84d3-e268fe827d05	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-29 12:49:29.728288+05:30	\N
d8b8db6c-98a8-4d38-9bac-3014614ca2ee	a636a2d8-d1c8-4111-84d3-e268fe827d05	assistant	### Notice Regarding Company Data\n\nI do **not** have access to NorthStar Bank's live internal loan portfolio or core banking systems. Therefore, I cannot provide your actual current delinquency rates or Non-Performing Loan (NPL) ratios. \n\nTo obtain exact figures for NorthStar Bank, you will need to run a report against your internal loan origination and servicing databases (e.g., querying your loan database for loans past due by product segment).\n\n---\n\n### General Knowledge: Industry Benchmarks & Definitions\n\n*(Category: General knowledge not specific to NorthStar Bank)*\n\nIn retail and commercial banking, metrics are typically categorized as follows:\n* **Delinquency Rate:** Percentage of total loans that are 30 to 89 days past due.\n* **NPL Ratio (Non-Performing Loan Ratio):** Percentage of total gross loans that are 90+ days past due, placed on non-accrual status, or in default.\n\nBelow is a general industry benchmark snapshot showing standard delinquency and NPL ranges typical for US commercial banks in recent economic cycles:\n\n| Product Line | Typical 30–89 Day Delinquency Rate | Typical NPL Ratio (90+ Days / Non-Accrual) | Risk Characteristics |\n| :--- | :--- | :--- | :--- |\n| **Residential Mortgages** | 1.0% – 1.8% | 0.6% – 1.2% | Low default, secured by real estate assets. |\n| **Credit Cards (Unsecured)** | 1.8% – 3.0% | 2.5% – 4.0% | Higher volatility; primary driver of retail charge-offs. |\n| **Auto Loans** | 1.2% – 2.5% | 0.8% – 1.5% | Secured, but depreciating collateral value. |\n| **Commercial Real Estate (CRE)** | 0.5% – 1.5% | 1.0% – 3.0% | Concentrated risk, heavily influenced by sector (e.g., office vs. industrial). |\n| **Commercial & Industrial (C&I)**| 0.4% – 1.0% | 0.7% – 1.5% | Dependent on macro cash flows and corporate health. |\n\n---\n\n### How to Retrieve NorthStar Bank's Actual Metrics\n\nTo extract your exact delinquency and NPL metrics from your data warehouse, your analytics team typically runs a calculation structured as:\n\n* **30–89 Day Delinquency Rate:**  \n  `SUM(Current Balance of Loans 30–89 Days Late) / SUM(Total Outstanding Principal Balance)`\n\n* **NPL Ratio:**  \n  `SUM(Current Balance of Loans 90+ Days Late + Non-Accrual Loans) / SUM(Total Outstanding Principal Balance)`\n\nGroup these calculations by your primary product dimensions (`product_line`, `segment`, or `loan_type`) for the current accounting period.	2026-08-29 12:49:29.74725+05:30	\N
ddf551bc-2cfc-426c-b71f-a7eb09338cad	1ac4441c-7a9a-462e-8312-4bd81d0cab49	user	Show transactions flagged as suspicious in the last 24 hours.	2026-08-29 13:03:08.306185+05:30	\N
fdc7c2a7-7a0c-4b78-9e2b-97e4330bb1e2	1ac4441c-7a9a-462e-8312-4bd81d0cab49	assistant	### Data Access Notice\n\nI do not have access to NorthStar Bank's live transactional database or Anti-Money Laundering (AML) flag systems. Therefore, I cannot provide real-time facts or specific transactional records for the last 24 hours. \n\nTo view actual flagged transactions, please query NorthStar Bank's internal AML/Fraud Monitoring platform or consult the compliance analytics dashboard.\n\n---\n\n### General Knowledge: Standard Suspicious Activity Flagging Criteria\n\nIn retail and commercial banking, automated transaction monitoring systems flag activities in real time based on pre-set rules and machine learning anomaly detection models. Typical triggers include:\n\n* **Structuring / Smurfing:** Multiple cash deposits or transfers just below regulatory reporting thresholds (e.g., under $10,000).\n* **Unusual Velocity:** A sudden, high volume of transactions within a very short timeframe on an account that is normally quiet.\n* **Geographic Anomaly:** Transactions originating from high-risk foreign jurisdictions or far outside a customer's typical spending radius.\n* **Rapid Movement of Funds:** Immediate transfer or withdrawal of newly deposited funds with no apparent business rationale.\n* **Uncharacteristic Large Transfers:** Wire transfers or ACH payments significantly exceeding historical account baseline activity.\n\n---\n\n### Example Workflow for Suspicious Transaction Triage\n\nBelow is a standard operational breakdown of how suspicious flags are typically categorized and handled by compliance teams:\n\n| Alert Severity | Trigger Example | Recommended Immediate Action |\n| :--- | :--- | :--- |\n| **High** | Sanctions list match or high-risk jurisdiction wire | Account freeze and immediate L2 AML analyst review |\n| **Medium** | High velocity or unusual rapid movement of funds | Temporary hold on outbound transfers pending customer verification |\n| **Low** | Off-pattern POS card transaction or minor geographic anomaly | Automated SMS/Email fraud alert sent to cardholder |\n\n*Note: The table above represents general banking industry practices and is not derived from NorthStar Bank's specific internal policy or real-time data.*	2026-08-29 13:03:08.315205+05:30	\N
ec00d17f-7fd2-4145-bb82-a084ee2b344c	a526f69a-46b9-4dcb-89ba-64931f19d7b9	user	Show transactions flagged as suspicious in the last 24 hours.	2026-08-29 13:03:43.499902+05:30	\N
f17f0eb4-8564-419a-97ec-f3698564f219	a526f69a-46b9-4dcb-89ba-64931f19d7b9	assistant	### Live Data Access Notice\n\nI do not have access to NorthStar Bank's live transactional database, Anti-Money Laundering (AML) monitoring systems, or real-time risk engines. Consequently, I cannot display specific account numbers, transaction IDs, or flagged events from the past 24 hours. To view active alerts, please query NorthStar Bank’s internal compliance portal (e.g., Actimize, FRAML, or core banking alert system).\n\n---\n\n### General Knowledge: Common Suspicious Transaction Indicators\n\nIn commercial and retail banking, automated transaction monitoring systems continuously screen activity against pre-defined rules and machine learning anomaly detection models. Suspicious activity flags typically fall into several key categories:\n\n* **Structuring / Smurfing:** Multiple cash deposits or transfers kept just below mandatory currency reporting thresholds (e.g., $10,000 in the U.S.).\n* **Velocity Anomalies:** A sudden, unexplained increase in the frequency or volume of transactions on an account with historically low activity.\n* **Geographic & IP Mismatches:** Transactions originating from high-risk sanctions jurisdictions or digital logins using suspicious VPN/proxy configurations.\n* **Rapid Movement of Funds (Pass-Through):** Immediate transfer or withdrawal of funds shortly after receipt, leaving near-zero balances.\n* **Unusual Wire Transfers:** High-value international wires inconsistent with the customer's known business profile or stated income.\n\n---\n\n### Illustrative Framework: Typical Daily AML Alert Breakdown\n\n*(AI projection / illustrative model — not verified against actual NorthStar Bank data)*\n\nBelow is an example of how a 24-hour suspicious activity alert summary is typically categorized for compliance review teams:\n\n| Alert Category | Risk Level | Common Trigger Condition | Standard Action |\n| :--- | :--- | :--- | :--- |\n| **Rapid Pass-Through** | High | Deposit followed immediately by international outgoing wire | Freeze funds & assign to Level 2 Analyst |\n| **Unusual Velocity** | Medium | >10 card-not-present transactions within 1 hour across distant locations | Temporary card lock & SMS verification |\n| **Threshold Structuring** | High | Multiple cash deposits between $8,500 and $9,900 within 24–48 hours | Queue for SAR (Suspicious Activity Report) review |\n| **Sanctions / PEP Match** | Critical | Counterparty name potential match on OFAC / PEP watchlists | Automated transaction hold & compliance escalation |\n| **New Device / IP Anomaly** | Low–Medium | Account login and transfer from unrecognized high-risk IP range | Step-up authentication (MFA) enforcement |	2026-08-29 13:03:43.515756+05:30	\N
cfbb270b-4092-4baf-b034-afc9df87fc1b	d6d066ba-329c-4f12-93fd-449bf2aa4253	user	What is our current delinquency rate and NPL ratio by product line?	2026-08-29 13:05:08.689245+05:30	\N
7d5025d7-6b01-49a2-b104-76c0139f96fb	d6d066ba-329c-4f12-93fd-449bf2aa4253	assistant	### Live Data Availability Notice\n\nI do not have access to NorthStar Bank's live portfolio data or internal financial systems. Therefore, I cannot provide the actual, specific current delinquency rates or Non-Performing Loan (NPL) ratios for NorthStar Bank's product lines. \n\nTo view NorthStar Bank's exact numbers, please consult your internal risk analytics dashboard, credit risk reporting suite, or regulatory filing reports (such as the Call Report / Form 10-Q).\n\n---\n\n### Industry Benchmarks & Context (General Knowledge)\n\n*Note: The figures below represent typical US banking industry benchmark ranges and general knowledge, NOT actual data from NorthStar Bank.*\n\nIn retail and commercial banking, **delinquency rates** (typically 30–80 days past due) and **NPL ratios** (90+ days past due or non-accrual status) vary significantly depending on asset class, collateral, and underwriting standards.\n\n| Product Line | Typical Delinquency Rate Range (30–80 Days) | Typical NPL Ratio Range (90+ Days / Non-Accrual) | Key Risk Drivers |\n| :--- | :--- | :--- | :--- |\n| **Residential Mortgages** | 1.5% – 2.5% | 0.5% – 1.2% | Interest rate changes, housing market liquidity, borrower unemployment. |\n| **Auto Loans** | 2.5% – 4.0% | 0.8% – 1.5% | Used vehicle depreciation, inflation on household budgets. |\n| **Credit Cards (Unsecured)** | 2.5% – 4.5% | 1.5% – 3.0% | Consumer cash flow pressure, unsecured credit exposure. |\n| **Commercial Real Estate (CRE)** | 1.0% – 3.0% | 1.5% – 4.5% | Office sector stress, refinancing risk at higher cap rates. |\n| **Commercial & Industrial (C&I)** | 1.0% – 2.0% | 0.5% – 1.5% | Macroeconomic downturns, supply chain pressures, industry-specific headwinds. |\n\n---\n\n### Key Definitions (General Knowledge)\n\n* **Delinquency Rate**: The percentage of loans within a product line that have missed scheduled payments (commonly categorized into 30–59 days past due and 60–89 days past due).\n* **Non-Performing Loan (NPL) Ratio**: The percentage of total gross loans that are 90+ days past due or placed on non-accrual status where full repayment of principal and interest is no longer expected.\n\n---\n\n### Recommended Next Steps for Internal Analysis\n\nTo generate this report from NorthStar Bank's data repository, query your data warehouse for:\n1. **Outstanding Principal Balance (UPB)** broken down by product segment.\n2. **Days Past Due (DPD)** buckets (30–59 DPD, 60–89 DPD, 90+ DPD).\n3. **Non-Accrual Flag** status across credit card, auto, mortgage, CRE, and C&I portfolios.	2026-08-29 13:05:08.696659+05:30	\N
d6d57046-0745-4ff5-b0fe-54a727d55ff8	d6d066ba-329c-4f12-93fd-449bf2aa4253	user	which tables have in to query	2026-08-29 13:05:50.060565+05:30	\N
2f458cdf-1dba-47a8-be39-a9fedc1d46af	d6d066ba-329c-4f12-93fd-449bf2aa4253	assistant	### Live Data Availability Notice\n\nI do not have access to NorthStar Bank's live data architecture, database schemas, or data dictionary. Therefore, I cannot name the exact table or column names used in your specific data warehouse. \n\nThe information below is based on **standard banking data warehouse models (General Knowledge)** to guide your data engineering or analytics team on where this information is typically stored.\n\n---\n\n### Standard Banking Database Tables (General Knowledge)\n\nIn a typical core banking system or Enterprise Data Warehouse (EDW), loan portfolio performance analytics require joining data across several key tables:\n\n| Standard Table Type | Common Table Names | Key Fields to Extract | Purpose |\n| :--- | :--- | :--- | :--- |\n| **Loan Master / Account** | `dim_loan`, `loan_master`, `account_fact` | `loan_id`, `customer_id`, `product_id`, `current_balance`, `origination_date`, `account_status` | Holds account-level balance and primary details. |\n| **Product Dimension** | `dim_product`, `product_hierarchy` | `product_id`, `product_name`, `product_line`, `asset_class` | Maps individual products to broader lines (e.g., Mortgages, Auto, CRE, C&I). |\n| **Loan Performance / Snapshot** | `fact_loan_snapshot`, `monthly_loan_status`, `loan_delinquency_daily` | `loan_id`, `as_of_date`, `days_past_due` (DPD), `is_non_accrual`, `delinquent_amount` | Contains historical and current DPD status and non-accrual flags. |\n| **Code Lookup / Status Reference** | `dim_status`, `ref_delinquency_bucket` | `status_code`, `dpd_bucket_description` | Translates numeric DPD into standard buckets (e.g., 30–59 DPD, 90+ DPD). |\n\n---\n\n### Standard Query Logic Example (General Knowledge)\n\nTo calculate delinquency rates and NPL ratios, a SQL query generally aggregates total balance and compares it to delinquent and non-accrual balances grouped by product line.\n\n```sql\nSELECT \n    p.product_line,\n    SUM(s.current_balance) AS total_portfolio_balance,\n    \n    -- Delinquency Rate (30-89 Days Past Due)\n    SUM(CASE WHEN s.days_past_due BETWEEN 30 AND 89 THEN s.current_balance ELSE 0 END) \n        / NULLIF(SUM(s.current_balance), 0) AS delinquency_rate,\n        \n    -- NPL Ratio (90+ Days Past Due OR Non-Accrual Status)\n    SUM(CASE WHEN s.days_past_due >= 90 OR s.is_non_accrual = 1 THEN s.current_balance ELSE 0 END) \n        / NULLIF(SUM(s.current_balance), 0) AS npl_ratio\n\nFROM fact_loan_snapshot s\nJOIN dim_loan l ON s.loan_id = l.loan_id\nJOIN dim_product p ON l.product_id = p.product_id\nWHERE s.as_of_date = CURRENT_DATE() -- Or end of most recent reporting month\nGROUP BY p.product_line;\n```\n\n---\n\n### Next Steps for NorthStar Bank Analytics\n\nTo get the exact schema mapping for NorthStar Bank:\n1. Contact your **Data Governance** or **Data Engineering** team for your bank's Data Dictionary or ERD (Entity Relationship Diagram).\n2. Check your business intelligence platform (e.g., Tableau, PowerBI, or Snowflake/BigQuery semantic layer) for pre-built views often named `vw_credit_risk_summary` or `vw_portfolio_performance`.	2026-08-29 13:05:50.067958+05:30	\N
1987530b-ab3a-44b2-ba71-74ce07d360f0	ab7689ec-239c-46b9-9b3f-d9b0e7a2037e	user	Show Loan Count for Auto Loan in Midwest for Retail	2026-09-03 16:26:14.396968+05:30	\N
898e6705-ab0b-4521-a075-2f05832448cf	5aa092d1-6744-43c2-aa7f-dafa78b2a39b	user	Show Loan Count for Auto Loan in Midwest for Retail	2026-09-03 16:26:51.006364+05:30	\N
74c70d0b-c517-4655-8f51-196f8cc224c2	5aa092d1-6744-43c2-aa7f-dafa78b2a39b	assistant	### Data Access Notice\nI do not have access to NorthStar Bank's live internal database or real-time transactional systems. Therefore, I cannot provide the exact actual loan count for Auto Loans in the Midwest region for the Retail segment. \n\nBelow is a breakdown categorizing what would typically be reported, an illustrative projection, and general industry context regarding this metric.\n\n---\n\n### 1. Facts Pulled from Real Company Data\n* **Status:** **Unavailable**  \n* To retrieve actual historical or current numbers, a query needs to be run directly against NorthStar Bank's core banking or loan origination system (e.g., filtering by `Product Type = 'Auto Loan'`, `Region = 'Midwest'`, and `Segment = 'Retail'`).\n\n---\n\n### 2. AI Projection / Hypothetical Scenario\n* **Label:** *AI projection / illustrative example, not verified against actual data.*\n\nIf you are running scenario modeling or forecasting based on standard regional retail banking distributions, a hypothetical monthly breakdown for the Midwest Retail Auto Loan portfolio might look like this:\n\n| State / Territory | Product Type | Segment | Projected Loan Count (Monthly) | Average Loan Size |\n| :--- | :--- | :--- | :--- | :--- |\n| Illinois | Auto Loan | Retail | 1,250 | $24,500 |\n| Ohio | Auto Loan | Retail | 980 | $22,800 |\n| Michigan | Auto Loan | Retail | 1,100 | $25,100 |\n| Indiana | Auto Loan | Retail | 750 | $21,900 |\n| Wisconsin | Auto Loan | Retail | 620 | $23,200 |\n| **Total Midwest** | **Auto Loan** | **Retail** | **4,700** | **$23,700 (Avg)** |\n\n---\n\n### 3. General Knowledge & Industry Context\n* **Regional Dynamics:** Auto loan demand in the Midwest Retail sector is heavily influenced by seasonal purchasing patterns (typically peaking in late spring and summer), local manufacturing economies, and prevailing interest rates.\n* **Retail Segment Characteristics:** Retail auto loans generally consist of direct consumer financing and indirect financing through auto dealerships. Retail borrowers in this region usually average loan terms between 60 to 72 months.\n* **Key Metrics to Track:** When analyzing this portfolio in your internal reporting systems, key metrics to evaluate alongside **Loan Count** include:\n  * Total Funded Volume ($)\n  * Average Approval Rate (%)\n  * 30+ Day Delinquency Rate (%)\n  * Yield / Weighted Average Interest Rate (%)	2026-09-03 16:26:51.027401+05:30	\N
f1af2c5a-0ea8-4240-89cf-47d0defd8721	a577d8df-76a0-44bc-beec-43af753ff7eb	user	Show Outstanding Balance for Personal Loan in Northeast for Retail	2026-09-03 19:11:11.021651+05:30	\N
c90f909b-ee90-4b1f-84b9-1e9b2da194ea	6a0bed81-381a-4149-8a41-e4bc32e73979	user	Show Outstanding Balance for Personal Loan in Northeast for Commercial	2026-09-03 19:11:45.180425+05:30	\N
dfb35753-8cdc-46a4-8b61-72546af4cc83	6a0bed81-381a-4149-8a41-e4bc32e73979	assistant	I do not have access to NorthStar Bank's live internal database or real-time ledger systems. Therefore, I cannot provide the actual, current outstanding balance for Personal Loans or Commercial segments in the Northeast region. \n\nTo give you a comprehensive answer, I have categorized the response into the three required perspectives below:\n\n---\n\n### 1. Real Company Data\n* **Status:** Unavailable.\n* **Details:** Pulling the precise, current outstanding balance for personal loans or commercial accounts in the Northeast region requires access to NorthStar Bank's internal core banking system or enterprise data warehouse. Since I do not have direct data integration, specific real-time figures cannot be displayed.\n\n---\n\n### 2. Projections & Illustrative Breakdown\n*(AI projection / Illustrative example — not verified against actual company data)*\n\nIf you were analyzing an estimated or projected portfolio distribution for the Northeast region, a standard analytical report would structure the data as follows:\n\n| Region | Portfolio Segment | Product Category | Projected Outstanding Balance ($M) | Est. Non-Performing Loan Rate |\n| :--- | :--- | :--- | :--- | :--- |\n| Northeast | Commercial Banking | Business Lines of Credit | $125.4M | 1.2% |\n| Northeast | Commercial Banking | Commercial Personal/Executive Loans | $18.6M | 0.8% |\n| Northeast | Retail / Consumer | Standard Personal Loans | $42.1M | 2.1% |\n| **Northeast Total** | **Combined** | **All Personal & Commercial** | **$186.1M** | **1.4%** |\n\n---\n\n### 3. General Knowledge & Industry Context\n*(General banking domain knowledge)*\n\nWhen analyzing loan balances across regional divisions and portfolio segments, commercial banks typically track several key factors:\n\n* **Segmentation Nuance:** "Personal Loans" usually fall under Consumer/Retail Banking, whereas "Commercial" refers to business entity financing. However, commercial divisions often track *Executive Personal Lines* or *Owner-Guaranteed Personal Loans* used for business cash flow purposes.\n* **Regional Dynamics (Northeast Market):** The Northeast commercial and consumer lending landscape is strongly influenced by regional economic factors, commercial real estate demand, and local interest rate sensitivity. \n* **Key Metrics Tracked:**\n  * **Gross Outstanding Balance:** The total principal remaining unpaid across active accounts.\n  * **Utilization Rate:** For lines of credit, the percentage of approved limit currently drawn.\n  * **Delinquency Status:** Balances categorized by payment status (e.g., 30-day, 60-day, or 90+ day past due).	2026-09-03 19:11:45.237647+05:30	\N
a9132158-ca59-487d-a5c4-d5ffead0641f	6a0bed81-381a-4149-8a41-e4bc32e73979	user	Show Total Principal for Personal Loan in Northeast for Commercial	2026-09-03 19:12:03.138187+05:30	\N
\.


--
-- Data for Name: data_source_connections; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.data_source_connections (id, tenant_id, platform, config, secret_ref, is_active, created_at) FROM stdin;
26fb6e07-5fa7-4fe7-aeab-926630061fce	22222222-2222-2222-2222-222222222222	databricks	{"host": "adb-7405615490948816.16.azuredatabricks.net", "schema": "Gold", "catalog": "deplearning", "warehouse_id": "f7bdf4d73ce15842"}	DATABRICKS_PAT	t	2026-08-13 19:11:29.956335+05:30
\.


--
-- Data for Name: genie_query_parameter_fields; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.genie_query_parameter_fields (id, tenant_id, user_id, field_name, options, display_order, created_at) FROM stdin;
d89aecf2-85cb-4bbc-8fd5-cbcea85bca4e	22222222-2222-2222-2222-222222222222	\N	Product Name	{"Auto Loan","Personal Loan","Credit Card",Mortgage,HELOC,"Business Loan"}	1	2026-09-03 15:35:33.720637+05:30
db6378df-6257-4549-8784-ac8a2951eddc	22222222-2222-2222-2222-222222222222	\N	Region	{Midwest,Northeast,South,West}	2	2026-09-03 15:35:33.720637+05:30
53751499-1a26-4ad6-a687-b4852de91c56	22222222-2222-2222-2222-222222222222	\N	Customer Segment	{Retail,"Small Business",Commercial,"Private Banking"}	3	2026-09-03 15:35:33.720637+05:30
894e54bf-c856-4553-8d87-a67fa4281fba	22222222-2222-2222-2222-222222222222	\N	Metric	{"Loan Count","Total Principal","Outstanding Balance","Delinquency Rate","NPL Ratio","Deposit Balance","New Accounts"}	5	2026-09-03 15:35:33.720637+05:30
\.


--
-- Data for Name: genie_question_templates; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.genie_question_templates (id, tenant_id, user_id, template) FROM stdin;
cb1e6d53-85a0-4609-8fab-f84fcae9f6d6	22222222-2222-2222-2222-222222222222	\N	Show {Metric} for {Product Name} in {Region} for {Customer Segment}
\.


--
-- Data for Name: genie_suggested_questions; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.genie_suggested_questions (id, tenant_id, user_id, question_text, display_order, created_at) FROM stdin;
ddec6c21-684c-4655-9182-e4323595d278	22222222-2222-2222-2222-222222222222	\N	Show loan portfolio by product.	2	2026-09-03 15:37:13.719699+05:30
60634f1e-b263-4594-8b3a-a2abe8ba88f3	22222222-2222-2222-2222-222222222222	\N	Show delinquency rate by product.	5	2026-09-03 15:37:13.719699+05:30
079105e4-01eb-44af-9c94-7bf7088d2f66	22222222-2222-2222-2222-222222222222	\N	What are the top performing loan products?	8	2026-09-03 15:37:13.719699+05:30
3dfb3e2f-94ed-4080-9235-ef7e543053c7	22222222-2222-2222-2222-222222222222	\N	Summarize overall banking portfolio health.	10	2026-09-03 15:37:13.719699+05:30
\.


--
-- Data for Name: governance_reviews; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.governance_reviews (id, tenant_id, user_id, question, check_type, reason, status, reviewed_by, reviewed_at, decision_note, created_at) FROM stdin;
\.


--
-- Data for Name: local_secrets; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.local_secrets (secret_ref, ciphertext, created_at, updated_at) FROM stdin;
local:databricks-pat:7d50d4b3-8286-4539-a6cb-22f9bfbff39c	gAAAAABqkdbfVrQgH5HfmG6XwsGyMhsXQa2nbeg9u3N3xzRZ5ji2dBuHPwcoJ1uoufWXKtjYTbKB9VNHaGczaeYmdy8YU3GDoP0DYCyQs3TEziqb7Vd4MuCWHg2hAMNyN1BsB2JycEqJ	2026-08-29 00:13:43.929335+05:30	2026-08-29 00:13:43.929335+05:30
local:llm-api-key:24732635-7243-4155-bb50-2194c054af7d	gAAAAABqkdbftQwA8YWgZkDNsCkrWdb-wZBlZs4D7ipJeL3nUS9yG-sNteWTU_3LPSqkYYKDB4bkijECRAS5uWNtoG_rq4LvwKt35ksrTl8o8qdaCzWFTA60e-AgNAxUQQ4Mlbp3epw_J8pNr734jo_zz48nJy_TcA==	2026-08-29 00:13:43.952094+05:30	2026-08-29 00:13:43.952094+05:30
local:databricks-pat:3afa92ae-abf4-4f9c-b2fa-edecac931796	gAAAAABqmR8GaQqq9lKd4DFmWPWG_FTpbO-tF7OediXEEY0xQRtd0LPoCHZ7XcznNEMXBYzVScWX5VRi5Gu0v88Hz_XLdmuIM5qsylkxP6cDMbsfM_vjJAlcYsbwzc3TRFoDwm091p2p	2026-09-03 12:47:26.600871+05:30	2026-09-03 12:47:26.600871+05:30
local:llm-api-key:6ee565f3-241d-40bd-90f6-7bf5117f1648	gAAAAABqmR8GeV5nMD9Ehra1yC0BWW2ZxHYSemmMS35nAUQoqydfZac3zivEghA1SquJc3CnND_t0FLxgnYCItg9YSWV0TzWWdLTtTSrqgaO7-uQJGZojUgGFenBVxKygWRl0uB18CeWUd9ctQOahJQ9h59-geU56g==	2026-09-03 12:47:26.642183+05:30	2026-09-03 12:47:26.642183+05:30
\.


--
-- Data for Name: pinned_items; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.pinned_items (id, tenant_id, user_id, source, item_type, title, payload, created_at) FROM stdin;
\.


--
-- Data for Name: schema_annotations; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.schema_annotations (id, tenant_id, catalog_name, schema_name, table_name, column_name, note, created_by, created_at) FROM stdin;
\.


--
-- Data for Name: use_cases; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.use_cases (id, tenant_id, title, description, category, sample_question, icon_key, created_at, generated_sql) FROM stdin;
c49b2a43-8608-40ab-9d60-9f801bcc27ef	22222222-2222-2222-2222-222222222222	Loan portfolio risk	Delinquency and non-performing loan trends across the portfolio.	Risk	What is our current delinquency rate and NPL ratio by product line?	alert-triangle	2026-08-26 02:20:36.841989+05:30	\N
6c66981b-27cc-4271-b4c9-9483d953b016	22222222-2222-2222-2222-222222222222	Loss ratio analysis	Analyze loss ratio across products and regions to identify high-risk segments and portfolio exposure.	Risk	Show the top 10 products and regions with the highest loss ratio for Q4 2025.	trending-up	2026-08-26 15:39:32.098678+05:30	SELECT\r\n        product_name,\r\n        region,\r\n        npl_ratio_pct AS loss_ratio,\r\n        total_outstanding_balance AS portfolio_balance\r\n     FROM\r\n        deplearning.gold.vw_loan_portfolio_summary\r\n     WHERE\r\n        year_num = 2025\r\n        AND quarter_num = 4\r\n        AND npl_ratio_pct IS NOT NULL\r\n     ORDER BY\r\n        npl_ratio_pct DESC\r\n     LIMIT 10
213dd587-01d9-41e6-9665-93b065d59d6f	22222222-2222-2222-2222-222222222222	Delinquency aging	How loans move through 30/60/90+ day past-due buckets over time.	Risk	Show me the delinquency aging buckets by product for the last two quarters	trending-up	2026-08-26 02:20:36.841989+05:30	\N
ba856290-dac7-40b4-9fa8-66ef11a5801b	22222222-2222-2222-2222-222222222222	Branch deposit performance	New account growth and deposit balances by branch and region.	Growth	Which branches had the strongest deposit growth this year?	building	2026-08-26 02:20:36.841989+05:30	\N
4c0662c7-86a6-461b-b62f-d8759670b192	22222222-2222-2222-2222-222222222222	Portfolio yield	Average interest rate and outstanding balance by product line.	Profitability	What is our average interest rate and total outstanding balance by product?	percent	2026-08-26 02:20:36.841989+05:30	\N
ba051f99-07cf-48fe-a7a8-11fb4cf5ef69	22222222-2222-2222-2222-222222222222	Charge-off exposure	Where charged-off balances are concentrated across the book.	Risk	Which product lines and regions have the highest charged-off balances?	trending-down	2026-08-26 02:20:36.841989+05:30	\N
\.


--
-- Data for Name: user_credentials; Type: TABLE DATA; Schema: tenant_22222222222222222222222222222222; Owner: -
--

COPY tenant_22222222222222222222222222222222.user_credentials (id, tenant_id, user_id, databricks_host, databricks_warehouse_id, databricks_genie_space_id, databricks_catalog, databricks_schema, databricks_pat_secret_ref, llm_provider, llm_api_key_secret_ref, last_validated_at, last_validation_ok, created_at, updated_at) FROM stdin;
4b47a5fd-cc28-4248-828c-3a13a77fbad1	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000001	adb-7405615490948816.16.azuredatabricks.net	f7bdf4d73ce15842	01f1a11b25be1822aaf7f54ad50b47b0	\N	\N	local:databricks-pat:7d50d4b3-8286-4539-a6cb-22f9bfbff39c	gemini	local:llm-api-key:24732635-7243-4155-bb50-2194c054af7d	2026-08-29 12:40:15.382176+05:30	t	2026-08-29 00:13:43.958353+05:30	2026-08-29 00:13:43.958353+05:30
c9491f2c-5ad3-49c7-b6f4-f09d5f48d9cf	22222222-2222-2222-2222-222222222222	b2222222-0000-0000-0000-000000000005	adb-7405615490948816.16.azuredatabricks.net	f7bdf4d73ce15842	01f1a11b25be1822aaf7f54ad50b47b0	\N	\N	local:databricks-pat:3afa92ae-abf4-4f9c-b2fa-edecac931796	gemini	local:llm-api-key:6ee565f3-241d-40bd-90f6-7bf5117f1648	\N	\N	2026-09-03 12:47:26.645706+05:30	2026-09-03 12:47:26.645706+05:30
\.


--
-- Name: chat_conversations chat_conversations_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.chat_conversations
    ADD CONSTRAINT chat_conversations_pkey PRIMARY KEY (id);


--
-- Name: chat_messages chat_messages_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.chat_messages
    ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id);


--
-- Name: data_source_connections data_source_connections_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.data_source_connections
    ADD CONSTRAINT data_source_connections_pkey PRIMARY KEY (id);


--
-- Name: genie_query_parameter_fields genie_query_parameter_fields_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.genie_query_parameter_fields
    ADD CONSTRAINT genie_query_parameter_fields_pkey PRIMARY KEY (id);


--
-- Name: genie_question_templates genie_question_templates_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.genie_question_templates
    ADD CONSTRAINT genie_question_templates_pkey PRIMARY KEY (id);


--
-- Name: genie_suggested_questions genie_suggested_questions_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.genie_suggested_questions
    ADD CONSTRAINT genie_suggested_questions_pkey PRIMARY KEY (id);


--
-- Name: governance_reviews governance_reviews_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.governance_reviews
    ADD CONSTRAINT governance_reviews_pkey PRIMARY KEY (id);


--
-- Name: local_secrets local_secrets_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.local_secrets
    ADD CONSTRAINT local_secrets_pkey PRIMARY KEY (secret_ref);


--
-- Name: pinned_items pinned_items_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.pinned_items
    ADD CONSTRAINT pinned_items_pkey PRIMARY KEY (id);


--
-- Name: schema_annotations schema_annotations_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.schema_annotations
    ADD CONSTRAINT schema_annotations_pkey PRIMARY KEY (id);


--
-- Name: use_cases use_cases_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.use_cases
    ADD CONSTRAINT use_cases_pkey PRIMARY KEY (id);


--
-- Name: user_credentials user_credentials_pkey; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.user_credentials
    ADD CONSTRAINT user_credentials_pkey PRIMARY KEY (id);


--
-- Name: user_credentials user_credentials_user_id_key; Type: CONSTRAINT; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE ONLY tenant_22222222222222222222222222222222.user_credentials
    ADD CONSTRAINT user_credentials_user_id_key UNIQUE (user_id);


--
-- Name: genie_question_templates_scope_idx; Type: INDEX; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE UNIQUE INDEX genie_question_templates_scope_idx ON tenant_22222222222222222222222222222222.genie_question_templates USING btree (tenant_id, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid));


--
-- Name: user_credentials_user_id_idx; Type: INDEX; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE INDEX user_credentials_user_id_idx ON tenant_22222222222222222222222222222222.user_credentials USING btree (user_id);


--
-- Name: data_source_connections; Type: ROW SECURITY; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE tenant_22222222222222222222222222222222.data_source_connections ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_query_parameter_fields genie_fields_visible; Type: POLICY; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE POLICY genie_fields_visible ON tenant_22222222222222222222222222222222.genie_query_parameter_fields USING (((tenant_id = public.current_tenant_id_safe()) AND ((user_id = public.current_user_id_safe()) OR (user_id IS NULL))));


--
-- Name: genie_query_parameter_fields; Type: ROW SECURITY; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE tenant_22222222222222222222222222222222.genie_query_parameter_fields ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_question_templates; Type: ROW SECURITY; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE tenant_22222222222222222222222222222222.genie_question_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_suggested_questions; Type: ROW SECURITY; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE tenant_22222222222222222222222222222222.genie_suggested_questions ENABLE ROW LEVEL SECURITY;

--
-- Name: genie_suggested_questions genie_suggestions_visible; Type: POLICY; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE POLICY genie_suggestions_visible ON tenant_22222222222222222222222222222222.genie_suggested_questions USING (((tenant_id = public.current_tenant_id_safe()) AND ((user_id = public.current_user_id_safe()) OR (user_id IS NULL))));


--
-- Name: genie_question_templates genie_template_visible; Type: POLICY; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE POLICY genie_template_visible ON tenant_22222222222222222222222222222222.genie_question_templates USING (((tenant_id = public.current_tenant_id_safe()) AND ((user_id = public.current_user_id_safe()) OR (user_id IS NULL))));


--
-- Name: data_source_connections query_parameters_visible; Type: POLICY; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE POLICY query_parameters_visible ON tenant_22222222222222222222222222222222.data_source_connections USING ((tenant_id = public.current_tenant_id_safe()));


--
-- Name: user_credentials; Type: ROW SECURITY; Schema: tenant_22222222222222222222222222222222; Owner: -
--

ALTER TABLE tenant_22222222222222222222222222222222.user_credentials ENABLE ROW LEVEL SECURITY;

--
-- Name: user_credentials user_owns_credentials; Type: POLICY; Schema: tenant_22222222222222222222222222222222; Owner: -
--

CREATE POLICY user_owns_credentials ON tenant_22222222222222222222222222222222.user_credentials USING (((tenant_id = public.current_tenant_id_safe()) AND (user_id = public.current_user_id_safe())));


--
-- PostgreSQL database dump complete
--

\unrestrict VZmBCMGB5jheUkP0zRjp2lreDRMdsZgJlmpDFc9SERcF0ubPzkHl6Djryk8VKat

