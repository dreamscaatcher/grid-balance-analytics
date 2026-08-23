"""Load pandas DataFrames into BigQuery raw tables.

Truncate-and-reload per table on each pipeline run (idempotent, no manual
cleanup needed) -- same approach as rail-ops-analytics.
"""
from __future__ import annotations

import logging

import pandas as pd
from google.cloud import bigquery

from pipeline.config import BQ_DATASET_RAW, BQ_LOCATION, GCP_PROJECT_ID

log = logging.getLogger(__name__)


def _client() -> bigquery.Client:
    return bigquery.Client(project=GCP_PROJECT_ID)


def ensure_dataset(dataset: str) -> None:
    client = _client()
    dataset_ref = bigquery.DatasetReference(GCP_PROJECT_ID, dataset)
    try:
        client.get_dataset(dataset_ref)
    except Exception:  # noqa: BLE001 -- not found, create it
        ds = bigquery.Dataset(dataset_ref)
        ds.location = BQ_LOCATION
        client.create_dataset(ds)
        log.info("created dataset %s", dataset)


def load_dataframe(df: pd.DataFrame, table: str, dataset: str = BQ_DATASET_RAW) -> None:
    if df.empty:
        log.warning("skipping load of %s.%s -- empty dataframe", dataset, table)
        return
    ensure_dataset(dataset)
    client = _client()
    table_id = f"{GCP_PROJECT_ID}.{dataset}.{table}"
    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_TRUNCATE")
    job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
    job.result()
    log.info("loaded %d rows into %s", len(df), table_id)
