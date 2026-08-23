"""Sanity checks that don't require network/API access."""
from pipeline.config import BZN_DE_LU_EIC, DWD_STATIONS, NEIGHBOURS_EIC


def test_eic_code_format():
    # ENTSO-E EIC codes are 16 characters.
    assert len(BZN_DE_LU_EIC) == 16
    assert all(len(eic) == 16 for eic in NEIGHBOURS_EIC.values())


def test_neighbours_non_empty():
    assert len(NEIGHBOURS_EIC) > 0


def test_dwd_stations_non_empty():
    assert len(DWD_STATIONS) > 0
