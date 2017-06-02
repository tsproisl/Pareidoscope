from distutils.core import setup

setup(
    name='Pareidoscope',
    version='0.1.0',
    author='Thomas Proisl',
    author_email='thomas.proisl@fau.de',
    packages=[
        'pareidoscope',
        'pareidoscope.utils'
    ],
    scripts=[
        'bin/pareidoscope_corpus_to_sqlite',
        'bin/pareidoscope_batch_query',
        'bin/pareidoscope_create_queries_from_corpus',
        'bin/pareidoscope_cwb_to_db',
        'bin/pareidoscope_distributed_batch_query_client',
        'bin/pareidoscope_distributed_batch_query_server',
        'pareidoscope_random_trees',
    ],
    # url='http://pypi.python.org/pypi/Pareidoscope/',
    license='GNU General Public License (GPL) 3.0',
    description='A tool for determining the association between arbitrary linguistic structures.',
    long_description=open('README.txt').read(),
    install_requires=[
        "networkx >= 1.6",
    ],
)
