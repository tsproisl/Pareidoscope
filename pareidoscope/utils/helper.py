#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import itertools
import math


def grouper_nofill(n, iterable):
    """list(grouper_nofill(3, 'ABCDEFG')) --> [['A', 'B', 'C'], ['D', 'E',
    'F'], ['G']]

    Arguments:
        n:
        iterable:

    """
    it = iter(iterable)
    def take():
        while True:
            yield list(itertools.islice(it, n))
    return iter(take().__next__, [])


def get_int_bins(min_value, max_value, nr_of_bins=10):
    """Find integer bin edges such that the bins are of equal size.
    
    Arguments:
        min_value:
        max_value:
        nr_of_bins:
    
    Returns:
        A list of bin edges.

    """
    bin_edges = None
    if max_value <= min_value + nr_of_bins - 1:
        bin_edges = list(range(min_value, max_value + 2))
    else:
        bin_size = int(math.ceil(float((max_value - min_value) + 1) / nr_of_bins))
        bin_edges = list(range(min_value, 1 + min_value + bin_size * nr_of_bins, bin_size))
    bin_edges[-1] = bin_edges[-1] - 1
    return bin_edges
