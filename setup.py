# python3 setup.py sdist
# python3 setup.py sdist upload

from os import path
from setuptools import setup

here = path.abspath(path.dirname(__file__))
with open(path.join(here, 'README.rst')) as fh:
    long_description = fh.read()

setup(
    name='Pareidoscope',
    version='0.9.0',
    author='Thomas Proisl',
    author_email='thomas.proisl@fau.de',
    packages=[
        'pareidoscope',
        'pareidoscope.utils'
    ],
    scripts=[
        'bin/pareidoscope_associated_structures',
        'bin/pareidoscope_association_strength',
        'bin/pareidoscope_collexeme_analysis',
        'bin/pareidoscope_corpus_to_sqlite',
        'bin/pareidoscope_covarying_collexemes',
        'bin/pareidoscope_draw_graphs',
    ],
    # url='http://pypi.python.org/pypi/Pareidoscope/',
    license='GNU General Public License v3 or later (GPLv3+)',
    description='A collection of tools for determining the association between arbitrary linguistic structures.',
    long_description=long_description,
    install_requires=[
        "networkx >= 1.6",
    ],
    classifiers=[
        'Development Status :: 4 - Beta',
        'Environment :: Console',
        'Intended Audience :: Developers',
        'Intended Audience :: Science/Research',
        'License :: OSI Approved :: GNU General Public License v3 or later (GPLv3+)',
        'Operating System :: OS Independent',
        'Programming Language :: Python :: 3',
        'Topic :: Text Processing :: Linguistic',
    ],
)
