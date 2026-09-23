"""The enrollment URI the QR encodes — DB-free (`db/enroll.enrollment_uri`)."""

from __future__ import annotations

from urllib.parse import parse_qs, urlsplit

import pytest

from healthee.core.enrollment import EnrollmentError
from healthee.db.enroll import enrollment_uri


def test_the_uri_carries_the_version_server_and_code_encoded() -> None:
    uri = enrollment_uri("https://health.example.com/ ", "a+b/c=d")
    parts = urlsplit(uri)
    assert (parts.scheme, parts.netloc) == ("healthee", "enroll")
    assert parse_qs(parts.query) == {
        "v": ["1"],
        "server": ["https://health.example.com"],
        "code": ["a+b/c=d"],
    }


@pytest.mark.parametrize(
    "server", ["health.example.com", "ftp://health.example.com", "https://", ""]
)
def test_a_server_the_phone_could_not_connect_to_is_refused(server: str) -> None:
    with pytest.raises(EnrollmentError):
        enrollment_uri(server, "code")
