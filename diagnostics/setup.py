#!/usr/bin/env python3
"""
Minimal setup for LED visualization tools

The Flutter app does all processing. This is only for visualization.
"""

from setuptools import setup

setup(
    name='led-visualizer',
    version='2.0.0',
    description='Minimal visualization tools for Flutter-generated LED positions',
    author='LED Mapper Team',
    python_requires='>=3.7',
    install_requires=[
        'numpy>=1.20.0',
        'matplotlib>=3.3.0',
    ],
    scripts=[
        'visualize.py',
    ],
    classifiers=[
        'Development Status :: 5 - Production/Stable',
        'Intended Audience :: Developers',
        'Topic :: Multimedia :: Graphics :: 3D Modeling',
        'Programming Language :: Python :: 3',
    ],
)
