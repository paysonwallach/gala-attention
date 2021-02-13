project(
  'gala-attention',
  'vala',
  'c',
  license: ['GPL3'],
  meson_version: '>=0.50.0',
  version: '0.1.0'
)

prefix = get_option('prefix')
libdir = join_paths(prefix, get_option('libdir'))
plugins_dir = join_paths(get_option('prefix'), get_option('libdir'), 'gala', 'plugins')
vapi_dir = join_paths(meson.current_source_dir(), 'vapi')

glib_version_required = '2.44.0'
gtk_version_required = '3.10.0'

gala_dep = dependency('gala')
gdk_dep = dependency('gdk-x11-3.0')
gee_dep = dependency('gee-0.8')
glib_dep = dependency('glib-2.0', version: '>= @0@'.format(glib_version_required))
gobject_dep = dependency('gobject-2.0', version: '>= @0@'.format(glib_version_required))
gio_unix_dep = dependency('gio-unix-2.0')
gio_dep = dependency('gio-2.0')

mutter_dep = []
libmutter_dep = []

vala_flags = []
c_flags = [
  '-DCLUTTER_ENABLE_COMPOSITOR_API',
  '-DCLUTTER_ENABLE_EXPERIMENTAL_API',
  '-DCOGL_ENABLE_EXPERIMENTAL_API',
  '-DCOGL_ENABLE_EXPERIMENTAL_2_0_API'
]

mutter336_dep = dependency('libmutter-6', version: ['>= 3.35.1', '< 3.37'], required: false)
if mutter336_dep.found()
  libmutter_dep = dependency('libmutter-6', version: '>= 3.35.1')
  mutter_dep = [
    dependency('mutter-cogl-6'), dependency('mutter-cogl-pango-6'),
    dependency('mutter-cogl-path-6'), dependency('mutter-clutter-6')
  ]
  vala_flags = ['--define', 'HAS_MUTTER330', '--define', 'HAS_MUTTER332', '--define', 'HAS_MUTTER334', '--define', 'HAS_MUTTER336']
endif

mutter338_dep = dependency('libmutter-7', version: ['>= 3.37'], required: false)
if mutter338_dep.found()
  libmutter_dep = dependency('libmutter-7', version: '>= 3.37')
  mutter_dep = [
    dependency('mutter-cogl-7'), dependency('mutter-cogl-pango-7'),
    dependency('mutter-clutter-7')
  ]
  vala_flags = ['--define', 'HAS_MUTTER330', '--define', 'HAS_MUTTER332', '--define', 'HAS_MUTTER334', '--define', 'HAS_MUTTER336', '--define', 'HAS_MUTTER338']
endif

if mutter_dep.length() == 0
  error ('No supported mutter library found!')
endif

mutter_typelib_dir = libmutter_dep.get_pkgconfig_variable('typelibdir')

add_project_arguments(
  '--vapidir=' + vapi_dir,
  language: 'vala',
)

subdir('lib')
