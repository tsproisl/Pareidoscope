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
    # 5:45
    group = []
    for element in iterable:
        group.append(element)
        if len(group) == n:
            yield group
            group = []
    if len(group) > 0:
        yield group
    # 6:20
    # sentinel = object()
    # return (itertools.filterfalse(lambda x: x is sentinel, chunk) for chunk in (itertools.zip_longest(*[iter(iterable)] * n, fillvalue=sentinel)))


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
