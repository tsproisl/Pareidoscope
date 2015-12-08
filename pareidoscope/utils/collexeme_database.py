#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sqlite3

def _connect_to_db(filename):
    """"""
    dirname = os.path.dirname(filename)
    conn = sqlite3.connect(filename)
    c = conn.cursor()
    c.execute("PRAGMA page_size=4096")
    c.execute("PRAGMA cache_size=100000")
    c.execute("PRAGMA temp_store=1")
    c.execute("PRAGMA temp_store_directory='%s'" % dirname)
    c.execute("CREATE TABLE IF NOT EXISTS queries (queryid INTEGER PRIMARY KEY AUTOINCREMENT, query TEXT, islemma BOOLEAN, collexeme_index INTEGER, wordclass TEXT, UNIQUE (query, islemma, collexeme_index, wordclass))")
    c.execute("CREATE TABLE IF NOT EXISTS associations (queryid INTEGER, collexeme TEXT, counting_method TEXT, dice REAL, gmean REAL, t_score REAL, log_likelihood REAL, o11 INTEGER, r1 INTEGER, c1 INTEGER, n INTEGER, UNIQUE(queryid, collexeme, counting_method), FOREIGN KEY (queryid) REFERENCES queries)")
    c.execute("CREATE TABLE IF NOT EXISTS correlations (queryid INTEGER, counting_method_1 TEXT, counting_method_2 TEXT, rho_dice REAL, rho_gmean REAL, rho_t_score REAL, rho_log_likelihood REAL, UNIQUE (queryid, counting_method_1, counting_method_2), FOREIGN KEY (queryid) REFERENCES queries)")
    return conn, c


def insert_results(db_filename, query, islemma, collexeme_index, wordclass, o11, r1, c1, n, dice_associations, gmean_associations, tscore_associations, ll_associations, dice_correlations, gmean_correlations, tscore_correlations, ll_correlations):
    """"""
    conn, c = _connect_to_db(db_filename)
    c.execute("INSERT OR IGNORE INTO queries (query, islemma, collexeme_index, wordclass) VALUES (?, ?, ?, ?)", (query, islemma, collexeme_index, wordclass))
    queryid = c.execute("SELECT queryid FROM queries WHERE query=? AND islemma=? AND collexeme_index=? AND wordclass=?", (query, islemma, collexeme_index, wordclass)).fetchall()[0][0]
    counting_methods = ["collostructional", "choke_points", "subgraphs", "isomorphisms"]
    get_freq = lambda freq, cm, starid: freq[cm] if cm == "collostructional" else freq[cm][starid]
    association_tuples = ((queryid, collexeme, counting_method, dice_associations[collexeme][counting_method], gmean_associations[collexeme][counting_method], tscore_associations[collexeme][counting_method], ll_associations[collexeme][counting_method], o11[counting_method][collexeme], r1[counting_method][collexeme], c1[counting_method], n[counting_method]) for collexeme in ll_associations.keys() for counting_method in counting_methods)
    c.executemany("INSERT OR IGNORE INTO associations (queryid, collexeme, counting_method, dice, gmean, t_score, log_likelihood, o11, r1, c1, n) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", association_tuples)
    correlation_tuples = ((queryid, cm1, cm2, dice_correlations[i][j], gmean_correlations[i][j], tscore_correlations[i][j], ll_correlations[i][j]) for i, cm1 in enumerate(counting_methods) for j, cm2 in enumerate(counting_methods))
    c.executemany("INSERT OR IGNORE INTO correlations (queryid, counting_method_1, counting_method_2, rho_dice, rho_gmean, rho_t_score, rho_log_likelihood) VALUES (?, ?, ?, ?, ?, ?, ?)", correlation_tuples)
    conn.commit()
    conn.close()
