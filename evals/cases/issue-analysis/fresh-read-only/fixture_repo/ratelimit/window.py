"""Fixed-window rate limiter used by the eval fixture."""


class Window:
    def __init__(self, limit):
        self.limit = limit
        self.count = 0

    def allow(self):
        self.count += 1
        return self.count <= self.limit + 1
