#!/usr/bin/env python

# python-gphoto2 - Python interface to libgphoto2
# http://github.com/jim-easterbrook/python-gphoto2
# Copyright (C) 2014-15  Jim Easterbrook  jim@jim-easterbrook.me.uk
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

from collections import defaultdict
from distutils.cmd import Command
from distutils.command.build import build
from distutils.command.upload import upload
from distutils.core import setup, Extension
import os
import re
import shlex
import subprocess
import sys

# python-gphoto2 version
version = '1.3.0-alpha'

# get gphoto2 library config
gphoto2_version = '.'.join(subprocess.check_output(
    ['pkg-config', '--modversion', 'libgphoto2'],
    universal_newlines=True).split('.')[:2])
gphoto2_flags = defaultdict(list)
for flag in subprocess.check_output(
        ['pkg-config', '--cflags', '--libs', 'libgphoto2'],
        universal_newlines=True).split():
    gphoto2_flags[flag[:2]].append(flag)
gphoto2_include  = gphoto2_flags['-I']
gphoto2_libs     = gphoto2_flags['-l']
gphoto2_lib_dirs = gphoto2_flags['-L']
for n in range(len(gphoto2_include)):
    if gphoto2_include[n].endswith('/gphoto2'):
        gphoto2_include[n] = gphoto2_include[n][:-len('/gphoto2')]

# create extension modules list
ext_modules = []
mod_src_dir = os.path.join('src', 'swig-bi-gp' + gphoto2_version +
                           '-py' + str(sys.version_info[0]))
if sys.version_info >= (3, 5) or not os.path.isdir(mod_src_dir):
    mod_src_dir = os.path.join('src', 'swig-gp' + gphoto2_version +
                               '-py' + str(sys.version_info[0]))
extra_compile_args = [
    '-O3', '-Wno-unused-variable', '-Wno-strict-prototypes', '-Werror']
libraries = [x.replace('-l', '') for x in gphoto2_libs]
library_dirs = [x.replace('-L', '') for x in gphoto2_lib_dirs]
include_dirs = [x.replace('-I', '') for x in gphoto2_include]
if os.path.isdir(mod_src_dir):
    for file_name in os.listdir(mod_src_dir):
        if file_name[-7:] != '_wrap.c':
            continue
        ext_name = file_name[:-7]
        ext_modules.append(Extension(
            '_' + ext_name,
            sources = [os.path.join(mod_src_dir, file_name)],
            libraries = libraries,
            library_dirs = library_dirs,
            include_dirs = include_dirs,
            extra_compile_args = extra_compile_args,
            ))

cmdclass = {}
command_options = {}

# add command to run SWIG
class build_swig(Command):
    description = 'run SWIG to regenerate interface files'
    user_options = []

    def initialize_options(self):
        pass

    def finalize_options(self):
        pass

    def run(self):
        # get list of modules (Python) and extensions (SWIG)
        file_names = os.listdir(os.path.join('src', 'gphoto2'))
        file_names.sort()
        file_names = [os.path.splitext(x) for x in file_names]
        ext_names = [x[0] for x in file_names if x[1] == '.i']
        mod_names = [x[0] for x in file_names if x[1] == '.py']
        # get gphoto2 versions to be swigged
        gp_versions = [gphoto2_version]
        if os.path.isdir('include'):
            for name in os.listdir('include'):
                match = re.match('gphoto2-(\d\.\d)', name)
                if match:
                    gp_version = match.group(1)
                    if gp_version not in gp_versions:
                        gp_versions.append(gp_version)
        self.announce('swigging gphoto2 versions %s' % str(gp_versions), 2)
        # do -builtin and not -builtin
        swig_bis = [False]
        swig_version = str(subprocess.check_output(
            ['swig', '-version'], universal_newlines=True))
        for line in swig_version.split('\n'):
            if 'Version' in line:
                swig_version = line.split()[-1]
                if swig_version != '2.0.11':
                    swig_bis.append(True)
                break
        for bi in swig_bis:
            # make options list
            swig_opts = ['-python', '-nodefaultctor', '-O', '-Isrc',
                         '-Wextra', '-Werror']
            if bi:
                swig_opts.append('-builtin')
            if sys.version_info[0] >= 3:
                swig_opts.append('-py3')
            # do each gphoto2 version
            for gp_version in gp_versions:
                output_dir = os.path.join('src', 'swig')
                if bi:
                    output_dir += '-bi'
                output_dir += '-gp' + gp_version
                output_dir += '-py' + str(sys.version_info[0])
                self.mkpath(output_dir)
                version_opts = [
                    '-DGPHOTO2_' + gp_version.replace('.', ''),
                    '-outdir', output_dir,
                    ]
                inc_dir = os.path.join('include', 'gphoto2-' + gp_version)
                if os.path.isdir(inc_dir):
                    version_opts.append('-I' + inc_dir)
                else:
                    version_opts += gphoto2_include
                # do each swig module
                for ext_name in ext_names:
                    in_file = os.path.join('src', 'gphoto2', ext_name + '.i')
                    out_file = os.path.join(output_dir, ext_name + '_wrap.c')
                    self.spawn(['swig'] + swig_opts + version_opts +
                               ['-o', out_file, in_file])
                # do each Python module
                for mod_name in mod_names:
                    in_file = os.path.join('src', 'gphoto2', mod_name + '.py')
                    out_file = os.path.join(output_dir, mod_name + '.py')
                    self.copy_file(in_file, out_file)
                # create init module
                init_file = os.path.join(output_dir, '__init__.py')
                with open(init_file, 'w') as im:
                    im.write('__version__ = "{}"\n\n'.format(version))
                    for name in mod_names + ext_names:
                        im.write('from gphoto2.{} import *\n'.format(name))

cmdclass['build_swig'] = build_swig

# modify upload class to add appropriate git tag
# requires GitPython - 'sudo pip install gitpython --pre'
try:
    import git
    class upload_and_tag(upload):
        def run(self):
            message = ''
            with open('CHANGELOG.txt') as cl:
                while not cl.readline().startswith('Changes'):
                    pass
                while True:
                    line = cl.readline().strip()
                    if not line:
                        break
                    message += line + '\n'
            repo = git.Repo()
            tag = repo.create_tag('v' + version, message=message)
            remote = repo.remotes.origin
            remote.push(tags=True)
            return upload.run(self)
    cmdclass['upload'] = upload_and_tag
except ImportError:
    pass

# set options for building distributions
command_options['sdist'] = {
    'formats' : ('setup.py', 'gztar zip'),
    }

# list example scripts
examples = [os.path.join('examples', x)
            for x in os.listdir('examples') if os.path.splitext(x)[1] == '.py']

with open('README.rst') as ldf:
    long_description = ldf.read()

setup(name = 'gphoto2',
      version = version,
      description = 'Python interface to libgphoto2',
      long_description = long_description,
      author = 'Jim Easterbrook',
      author_email = 'jim@jim-easterbrook.me.uk',
      url = 'https://github.com/jim-easterbrook/python-gphoto2',
      classifiers = [
          'Development Status :: 5 - Production/Stable',
          'Intended Audience :: Developers',
          'License :: OSI Approved :: GNU General Public License v3 or later (GPLv3+)',
          'Operating System :: MacOS',
          'Operating System :: MacOS :: MacOS X',
          'Operating System :: POSIX',
          'Operating System :: POSIX :: BSD :: FreeBSD',
          'Operating System :: POSIX :: BSD :: NetBSD',
          'Operating System :: POSIX :: Linux',
          'Programming Language :: Python :: 2',
          'Programming Language :: Python :: 2.6',
          'Programming Language :: Python :: 2.7',
          'Programming Language :: Python :: 3',
          'Topic :: Multimedia',
          'Topic :: Multimedia :: Graphics',
          'Topic :: Multimedia :: Graphics :: Capture',
          ],
      platforms = ['POSIX', 'MacOS'],
      license = 'GNU GPL',
      cmdclass = cmdclass,
      command_options = command_options,
      ext_package = 'gphoto2',
      ext_modules = ext_modules,
      packages = ['gphoto2'],
      package_dir = {'gphoto2' : mod_src_dir},
      data_files = [
          ('share/python-gphoto2/examples', examples),
          ('share/python-gphoto2', [
              'CHANGELOG.txt', 'LICENSE.txt', 'README.rst']),
          ],
      )
