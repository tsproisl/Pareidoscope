#!/usr/bin/python
# -*- coding: utf-8 -*-for

def get_contingency_table(o11, r1, c1, n):
    """Fill in the values for O11, O12, O21 and O22 and E11, E12, E21 and
    E22.
    
    Args:
        o11:
        r1:
        c1:
        n:

    """
    o, e = {}, {}
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


