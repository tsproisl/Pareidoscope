#!/usr/bin/python
# -*- coding: utf-8 -*-for

import math

def get_contingency_table(o11, r1, c1, n):
    """Fill in the values for O11, O12, O21 and O22 and E11, E12, E21 and
    E22.
    
    Args:
        o11:
        r1:
        c1:
        n:

    """
    o, e = {1: {}, 2: {}}, {1: {}, 2: {}}
    r2 = n - r1
    c2 = n - c1
    o[1][1] = o11
    o[1][2] = r1 - o11
    o[2][1] = c1 - o11
    o[2][2] = r2 - o[2][1]
    e[1][1] = r1 * c1 / float(n)
    e[1][2] = r1 * c2 / float(n)
    e[2][1] = r2 * c1 / float(n)
    e[2][2] = r2 * c2 / float(n)
    return o, e


def log_likelihood(o, e):
    """Calculate the log-likelihood measure

    Args:
        o:
        e:

    """
    ll = 0
    for r in o:
        for c in o[r]:
            if o[r][c] == 0:
                continue
            ll += o[r][c] * math.log(float(o[r][c]) / e[r][c], 2)
    ll *= 2
    return ll


def mutual_information(o, e):
    """Calculate the mutual information measure

    Args:
        o:
        e:

    """
    return math.log(o[1][1] / e[1][1], 2)


def dice(o, e):
    """Calculate the Dice measure

    Args:
        o:
        e:

    """
    r1 = o[1][1] + o[1][2]
    c1 = o[1][1] + o[2][1]
    return (2 * o[1][1]) / (r1 + c1)


def jaccard(o, e):
    """Calculate the Jaccard measure

    Args:
        o:
        e:

    """
    return o[1][1] / (o[1][1] + o[1][2] + o[2][1])

