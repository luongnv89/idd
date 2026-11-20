from ratelimit.window import Window


def test_first_request_allowed():
    assert Window(2).allow()
