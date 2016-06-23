#!/usr/bin/python
# -*- coding: utf-8 -*-

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
    o[1][1] = float(o11)
    o[1][2] = float(r1 - o11)
    o[2][1] = float(c1 - o11)
    o[2][2] = float(r2 - o[2][1])
    e[1][1] = r1 * c1 / float(n)
    e[1][2] = r1 * c2 / float(n)
    e[2][1] = r2 * c1 / float(n)
    e[2][2] = r2 * c2 / float(n)
    return o, e


def poisson_stirling_log(o, e):
    """Calculate the Poisson-Stirling measure

    Args:
        o:
        e:

    """
    return o[1][1] * (math.log(o[1][1], 2) - math.log(e[1][1], 2) - 1)


def z_score(o, e):
    """Calculate the z-score measure

    Args:
        o:
        e:

    """
    return (o[1][1] - e[1][1]) / math.sqrt(e[1][1])


def t_score(o, e):
    """Calculate the t-score measure

    Args:
        o:
        e:

    """
    return (o[1][1] - e[1][1]) / math.sqrt(o[1][1])


def chi_squared(o, e):
    """Calculate the chi-squared measure

    Args:
        o:
        e:

    """
    n = o[1][1] + o[1][2] + o[2][1] + o[2][2]
    return (n * (o[1][1] - e[1][1]) ** 2) / (e[1][1] * e[2][2])


def one_sided_chi_squared(o, e):
    """Calculate the one-sided chi-squared measure

    Args:
        o:
        e:

    """

    if o[1][1] < e[1][1]:
        return -1.0 * chi_squared(o, e)
    else:
        return chi_squared(o, e)


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
            ll += o[r][c] * math.log(o[r][c] / e[r][c], 2)
    ll *= 2
    return ll


def one_sided_log_likelihood(o, e):
    """Calculate the one-sided log-likelihood measure

    Args:
        o:
        e:

    """
    if o[1][1] < e[1][1]:
        return -1.0 * log_likelihood(o, e)
    else:
        return log_likelihood(o, e)


def mutual_information(o, e):
    """Calculate the mutual information measure

    Args:
        o:
        e:

    """
    return math.log(o[1][1] / e[1][1], 2)


def local_mi(o, e):
    """Calculate the local mutual information measure

    Args:
        o:
        e:

    """
    return o[1][1] * mutual_information(o, e)


def average_mi(o, e):
    """Calculate the average mutual information measure (= log-likelihood)

    Args:
        o:
        e:

    """
    return log_likelihood(o, e)


def mi2(o, e):
    """Calculate the heuristic MI^2 measure

    Args:
        o:
        e:

    """
    return math.log(o[1][1] ** 2 / e[1][1], 2)


def mi3(o, e):
    """Calculate the heuristic MI^3 measure

    Args:
        o:
        e:

    """
    return math.log(o[1][1] ** 3 / e[1][1], 2)


def odds_ratio_disc(o, e):
    """Calculate the discounted odds-ratio measure

    Args:
        o:
        e:

    """
    return math.log(((o[1][1] + 0.5) * (o[2][2] + 0.5)) / ((o[1][2] + 0.5) * (o[2][1] + 0.5)), 2)


def relative_risk(o, e):
    """Calculate the relative-risk measure

    Args:
        o:
        e:

    """
    c1 = o[1][1] + o[2][1]
    c2 = o[1][2] + o[2][2]
    return math.log((o[1][1] * c2) / (o[1][2] * c1), 2)


def liddell(o, e):
    """Calculate the Liddell measure

    Args:
        o:
        e:

    """
    c1 = o[1][1] + o[2][1]
    c2 = o[1][2] + o[2][2]
    return (o[1][1] * o[2][2] - o[1][2] * o[2][1]) / (c1 * c2)


def minimum_sensitivity(o, e):
    """Calculate the minimum-sensitivity measure

    Args:
        o:
        e:

    """
    r1 = o[1][1] + o[1][2]
    c1 = o[1][1] + o[2][1]
    return min(o[1][1] / r1, o[1][1] / c1)


def geometric_mean(o, e):
    """Calculate the gmean measure

    Args:
        o:
        e:

    """
    r1 = o[1][1] + o[1][2]
    c1 = o[1][1] + o[2][1]
    return o[1][1] / math.sqrt(r1 * c1)


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


def cooccurrence_frequency(o, e):
    """Return O11

    Args:
        o:
        e:

    """
    return o[1][1]


def delta_p_column(o, e):
    """Calculate the column-wise delta P measure, i.e. the difference of
    column proportions (= Liddell).

    Args:
        o:
        e:

    """
    return liddell(o, e)


def delta_p_row(o, e):
    """Calculate the row-wise delta P measure, i.e. the difference of row
    proportions.

    Args:
        o:
        e:

    """
    r1 = o[1][1] + o[1][2]
    r2 = o[2][1] + o[2][2]
    return (o[1][1] * o[2][2] - o[1][2] * o[2][1]) / (r1 * r2)


def max_delta_p(o, e):
    """Return the maximum of the column-wise and the row-wise delta P
    measure.

    Args:
        o:
        e:

    """
    return max(delta_p_row(o, e), delta_p_column(o, e))
