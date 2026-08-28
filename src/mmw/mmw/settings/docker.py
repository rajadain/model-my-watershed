import os

os.environ.setdefault('MMW_DB_HOST', 'postgres')
os.environ.setdefault('MMW_DB_NAME', 'mmw')
os.environ.setdefault('MMW_DB_USER', 'mmw')
os.environ.setdefault('MMW_DB_PASSWORD', 'mmw')
os.environ.setdefault('MMW_DB_PORT', '5432')
os.environ.setdefault('MMW_CACHE_HOST', 'redis')
os.environ.setdefault('MMW_CACHE_PORT', '6379')
os.environ.setdefault('DJANGO_SECRET_KEY', 'development-secret-key')
os.environ.setdefault('DJANGO_STATIC_ROOT', '/var/www/mmw/static')
os.environ.setdefault('DJANGO_MEDIA_ROOT', '/var/www/mmw/media')
os.environ.setdefault('MMW_TILER_HOST', 'localhost:4000')
os.environ.setdefault('MMW_GEOPROCESSING_HOST', 'geop')
os.environ.setdefault('MMW_GEOPROCESSING_PORT', '8090')
os.environ.setdefault('MMW_GEOPROCESSING_VERSION', '6.1.0')
os.environ.setdefault('RWD_HOST', 'rwd')
os.environ.setdefault('RWD_PORT', '5000')

from mmw.settings.development import *  # NOQA

ALLOWED_HOSTS = list(set(ALLOWED_HOSTS + [
    'app',
    'localhost',
    '127.0.0.1',
]))
