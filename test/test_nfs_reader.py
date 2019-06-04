from pathlib import Path

import cudf
import pandas
import pytest

from rapidscyber.factory.factory import Factory
from rapidscyber.reader.nfs_reader import NFSReader
from rapidscyber.writer.nfs_writer import NFSWriter

test_input_base_path = str(Path("test_input").resolve())
expected_df = cudf.DataFrame(
    [
        ("firstname", ["Emma", "Ava", "Sophia"]),
        ("lastname", ["Olivia", "Isabella", "Charlotte"]),
        ("gender", ["F", "F", "F"]),
    ]
).to_pandas()


@pytest.mark.parametrize("test_input_base_path", [test_input_base_path])
@pytest.mark.parametrize("expected_df", [expected_df])
def test_fetch_data_text(test_input_base_path, expected_df):
    test_input_path = "%s/person.csv" % (test_input_base_path)
    config = {
        "input_path": test_input_path,
        "schema": ["firstname", "lastname", "gender"],
        "delimiter": ",",
        "required_cols": ["firstname", "lastname", "gender"],
        "dtype": ["str", "str", "str"],
        "header": 0,
        "input_format": "text",
    }
    reader = NFSReader(config)
    fetched_df = reader.fetch_data()
    assert fetched_df.to_pandas().equals(expected_df)

    reader_from_factory = Factory.getIOReader("nfs", config)
    fetched_df2 = reader_from_factory.fetch_data()
    assert fetched_df2.to_pandas().equals(expected_df)


@pytest.mark.parametrize("test_input_base_path", [test_input_base_path])
@pytest.mark.parametrize("expected_df", [expected_df])
def test_fetch_data_parquet(test_input_base_path, expected_df):
    test_input_path = "%s/person.parquet" % (test_input_base_path)
    config = {
        "input_path": test_input_path,
        "required_cols": ["firstname", "lastname", "gender"],
        "input_format": "parquet",
    }

    reader = NFSReader(config)
    fetched_df = reader.fetch_data()
    assert fetched_df.to_pandas().equals(expected_df)

    reader_from_factory = Factory.getIOReader("nfs", config)
    fetched_df2 = reader_from_factory.fetch_data()
    assert fetched_df2.to_pandas().equals(expected_df)


@pytest.mark.parametrize("test_input_base_path", [test_input_base_path])
@pytest.mark.parametrize("expected_df", [expected_df])
def test_fetch_data_orc(test_input_base_path, expected_df):
    test_input_path = "%s/person.orc" % (test_input_base_path)
    config = {
        "input_path": test_input_path,
        "required_cols": ["firstname", "lastname", "gender"],
        "input_format": "orc",
    }

    reader = NFSReader(config)
    fetched_df = reader.fetch_data()
    assert fetched_df.to_pandas().equals(expected_df)

    reader_from_factory = Factory.getIOReader("nfs", config)
    fetched_df2 = reader_from_factory.fetch_data()
    assert fetched_df2.to_pandas().equals(expected_df)
