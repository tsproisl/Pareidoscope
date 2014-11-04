#!/usr/bin/python
# -*- coding: utf-8 -*-

import functools
import itertools
import multiprocessing

def _unpack_args(function):
    """"""
    def function_taking_tuple (arguments):
        function(*arguments)
    return function_taking_tuple


def map_reduce(map_function, reduce_function, arguments, processes=multiprocessing.cpu_count(), groupsize_multiplier=500, chunksize=10):
    """Parallel processing of the elements in arguments and reduction to a
    single value.
    
    Arguments:
        map_function:
        reduce_function:
        arguments: An iterable
        processes: Number of processes; default: number of cpus
        groupsize_multiplier: How many arguments per process in one go
        chunksize: 

    Returns:
        The result of reduce(reduce_function, map(map_function, arguments)).

    """
    groupsize = processes * groupsize_multiplier
    pool = multiprocessing.Pool(processes=processes)
    
    map_f = _unpack_args(map_function)
    reduce_f = _unpack_args(reduce_function)

    results = reduce(reduce_f, pool.imap_unordered(map_f, arguments, chunksize=chunksize))
    return results
