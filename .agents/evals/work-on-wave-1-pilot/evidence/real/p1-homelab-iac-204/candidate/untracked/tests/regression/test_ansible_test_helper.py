"""Contract tests for the shared Ansible regression-test invocation helper."""

from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/ansible"


def load_helper() -> ModuleType:
    helper_path = Path(__file__).with_name("ansible_test_helper.py")
    spec = importlib.util.spec_from_file_location("ansible_test_helper", helper_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def set_fixture_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ANSIBLE_INVENTORY", str(FIXTURE_ROOT / "inventory.yml"))
    monkeypatch.setenv(
        "ANSIBLE_VAULT_PASSWORD_FILE", str(FIXTURE_ROOT / "vault-pass")
    )


def test_constructs_locked_playbook_invocation_with_fixture_environment(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    set_fixture_environment(monkeypatch)
    helper = load_helper()

    assert helper.ansible_playbook_command("fixture.yml", "--check") == [
        "uv",
        "run",
        "--locked",
        "ansible-playbook",
        "fixture.yml",
        "--check",
    ]


@pytest.mark.parametrize(
    ("variable", "value"),
    [
        ("ANSIBLE_INVENTORY", None),
        ("ANSIBLE_INVENTORY", "/different/inventory.yml"),
        ("ANSIBLE_VAULT_PASSWORD_FILE", None),
        ("ANSIBLE_VAULT_PASSWORD_FILE", "/different/vault-pass"),
    ],
)
def test_fixture_environment_failure_names_the_supported_test_command(
    monkeypatch: pytest.MonkeyPatch,
    variable: str,
    value: str | None,
) -> None:
    set_fixture_environment(monkeypatch)
    if value is None:
        monkeypatch.delenv(variable)
    else:
        monkeypatch.setenv(variable, value)
    helper = load_helper()

    with pytest.raises(AssertionError, match=r"\./validate\.sh tests"):
        helper.ansible_playbook_command("fixture.yml")


def test_explicit_own_inventory_mode_retains_the_vault_fixture_guard(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    set_fixture_environment(monkeypatch)
    monkeypatch.delenv("ANSIBLE_INVENTORY")
    helper = load_helper()

    assert helper.ansible_playbook_command(
        "fixture.yml",
        "--inventory",
        "test-inventory.yml",
        supplies_own_inventory=True,
    ) == [
        "uv",
        "run",
        "--locked",
        "ansible-playbook",
        "fixture.yml",
        "--inventory",
        "test-inventory.yml",
    ]


def test_own_inventory_mode_still_requires_the_fixture_vault_password_file(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    set_fixture_environment(monkeypatch)
    monkeypatch.delenv("ANSIBLE_INVENTORY")
    monkeypatch.delenv("ANSIBLE_VAULT_PASSWORD_FILE")
    helper = load_helper()

    with pytest.raises(AssertionError, match=r"\./validate\.sh tests"):
        helper.ansible_playbook_command(
            "fixture.yml",
            "--inventory",
            "test-inventory.yml",
            supplies_own_inventory=True,
        )


def test_fixture_inventory_contains_only_unaddressed_test_hosts() -> None:
    inventory = yaml.safe_load(
        (FIXTURE_ROOT / "inventory.yml").read_text(encoding="utf-8")
    )

    assert inventory == {
        "all": {
            "hosts": {
                "auth": None,
                "portal": None,
                "workstation": None,
            }
        }
    }
