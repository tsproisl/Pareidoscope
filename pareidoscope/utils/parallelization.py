#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import functools
import multiprocessing

def _unpack_args(function):
    """Wrapper around function that accepts arguments as a single
    tuple."""
    def function_taking_tuple(arguments):
        function(*arguments)
    return function_taking_tuple


def map_reduce(map_function, reduce_function, map_arguments, reduce_arguments, processes=multiprocessing.cpu_count(), groupsize_multiplier=500, chunksize=10):
    """Parallel processing of the elements in arguments and reduction to a
    single value.
    
    Arguments:
        map_function:
        reduce_function:
        map_arguments: An iterable
        reduce_arguments: Additional arguments to reduce_function,
            passed as first arguments
        processes: Number of processes; default: number of cpus
        groupsize_multiplier: How many arguments per process in one go
        chunksize: 

    Returns:
        The result of reduce(reduce_function, reduce_arguments, map(map_function, map_arguments)).

    """
    groupsize = processes * groupsize_multiplier
    pool = multiprocessing.Pool(processes=processes)
    
    map_f = _unpack_args(map_function)
    reduce_f = functools.partial(reduce_function, *reduce_arguments)

    results = functools.reduce(reduce_f, pool.imap_unordered(map_f, arguments, chunksize=chunksize))
    return results
