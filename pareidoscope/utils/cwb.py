#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re


def sentences_iter(corpus, return_id=False):
    """Iterate over the sentences in a corpus.

    Arguments:
    - `corpus`:
    """
    pattern = re.compile(r"\bid=(['\"])([^'\"]+)\1")
    origid = ""
    sentence = []
    for line in corpus:
        line = line.rstrip("\n")
        if line == "</s>":
            if return_id:
                yield sentence, origid
            else:
                yield sentence
        elif line.startswith("<s "):
            m = re.search(pattern, line)
            if m:
                origid = m.group(2)
            else:
                raise Exception("Line does not match: %s" % line)
            sentence = []
        elif line.startswith("<"):
            pass
        else:
            sentence.append(line.split("\t"))
