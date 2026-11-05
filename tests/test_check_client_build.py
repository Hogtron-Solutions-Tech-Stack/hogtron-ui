# dev/check_client_build.py: the launcher's .build.info against the toc Interface numbers we ship.
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("check_client_build", ROOT / "dev" / "check_client_build.py")
CB = importlib.util.module_from_spec(spec)
spec.loader.exec_module(CB)

# verbatim shape of the launcher file (2026-11-03), key ring column blank
BUILD_INFO = (
    "Branch!STRING:0|Last Activated!STRING:0|Version!STRING:0|KeyRing!HEX:16|Product!STRING:0\n"
    "us||1.15.9.70576||wow_classic_era\n"
    "us||2.5.6.70577||wow_anniversary\n"
    "us||1.60.1.70755||wowf\n"
)


def test_parse_reads_columns_by_header_name_not_position():
    rows = CB.parse_build_info(BUILD_INFO)
    assert [(r["Product"], r["Version"]) for r in rows] == [
        ("wow_classic_era", "1.15.9.70576"), ("wow_anniversary", "2.5.6.70577"), ("wowf", "1.60.1.70755")]
    swapped = "Product!STRING:0|Version!STRING:0\nwowf|1.60.2.1\n"
    assert CB.parse_build_info(swapped)[0] == {"Product": "wowf", "Version": "1.60.2.1"}
    assert CB.parse_build_info("") == []


def test_toc_from_version():
    assert CB.toc_from_version("1.60.1.70755") == 16001
    assert CB.toc_from_version("2.5.6.70577") == 20506
    assert CB.toc_from_version("1.15.9") == 11509
    assert CB.toc_from_version("1.61.0.1") == 16100
    assert CB.toc_from_version("") is None
    assert CB.toc_from_version("beta") is None


def test_every_shipped_toc_lists_the_same_interface_numbers():
    tocs = CB.toc_interfaces(ROOT)
    assert len(tocs) >= 15
    assert len({tuple(v) for v in tocs.values()}) == 1, tocs


def test_installed_clients_covered_by_the_tocs_pass():
    shipped = [20505, 20506, 11508, 11509, 16001]
    lines, bad = CB.check(CB.parse_build_info(BUILD_INFO), shipped)
    assert bad == []
    assert sum(l.startswith("OK ") for l in lines) == 3


def test_a_patched_client_is_out_of_date_and_names_the_toc_it_needs():
    patched = BUILD_INFO.replace("1.60.1.70755", "1.60.2.70900")
    lines, bad = CB.check(CB.parse_build_info(patched), [20505, 20506, 11508, 11509, 16001])
    assert bad == ["wowf"]
    hit = [l for l in lines if l.startswith("OUT OF DATE")]
    assert len(hit) == 1 and "-> 16002" in hit[0] and "WoW: Forever" in hit[0]


def test_untargeted_and_missing_products_never_fail():
    text = "Version!STRING:0|Product!STRING:0\n12.0.1.1|wow\n5.5.4.1|wow_classic\n"
    lines, bad = CB.check(CB.parse_build_info(text), [16001])
    assert bad == []
    assert sum(l.startswith("skip") for l in lines) == 2
    assert sum(l.startswith("absent") for l in lines) == 3


def test_main_exit_codes(tmp_path):
    bi = tmp_path / "build.info"
    bi.write_text(BUILD_INFO, encoding="utf-8")
    assert CB.main(["--build-info", str(bi)]) == 0
    bi.write_text(BUILD_INFO.replace("2.5.6.70577", "2.5.7.1"), encoding="utf-8")
    assert CB.main(["--build-info", str(bi)]) == 1
    assert CB.main(["--build-info", str(tmp_path / "nope")]) == 1
