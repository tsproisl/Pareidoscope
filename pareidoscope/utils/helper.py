#!/usr/bin/python
# -*- coding: utf-8 -*-

import itertools


def grouper_nofill(n, iterable):
    """list(grouper_nofill(3, 'ABCDEFG')) --> [['A', 'B', 'C'], ['D', 'E',
    'F'], ['G']]

    Arguments:
    - `n`:
    - `iterable`:

    """
    it = iter(iterable)
    def take():
        while True:
            yield list(itertools.islice(it, n))
    return iter(take().next, [])
