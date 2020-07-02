FROM node:14 as frontend

# Compile static files
COPY ./wagtail /wagtail
RUN cd /wagtail && npm install --no-optional --no-audit --progress=false
RUN cd /wagtail && npm run dist

# We use Debian images because they are considered more stable than the alpine
# ones becase they use a different C compiler. Debian images also come with
# all useful packages required for image manipulation out of the box. They
# however weight a lot, approx. up to 1.5GiB per built image.
FROM python:3.7-stretch as backend

ARG POETRY_HOME=/opt/poetry
ARG POETRY_VERSION=1.0.3

RUN useradd bakerydemo
RUN mkdir -p /home/bakerydemo
RUN chown bakerydemo /home/bakerydemo

WORKDIR /app

# Set default environment variables. They are used at build time and runtime.
# If you specify your own environment variables on Heroku or Dokku, they will
# override the ones set here. The ones below serve as sane defaults only.
#  * PATH - Make sure that Poetry is on the PATH
#  * PYTHONUNBUFFERED - This is useful so Python does not hold any messages
#    from being output.
#    https://docs.python.org/3.8/using/cmdline.html#envvar-PYTHONUNBUFFERED
#    https://docs.python.org/3.8/using/cmdline.html#cmdoption-u
#  * PYTHONPATH - enables use of django-admin command.
#  * DJANGO_SETTINGS_MODULE - default settings used in the container.
#  * PORT - default port used. Please match with EXPOSE so it works on Dokku.
#    Heroku will ignore EXPOSE and only set PORT variable. PORT variable is
#    read/used by Gunicorn.
#  * WEB_CONCURRENCY - number of workers used by Gunicorn. The variable is
#    read by Gunicorn.
#  * GUNICORN_CMD_ARGS - additional arguments to be passed to Gunicorn. This
#    variable is read by Gunicorn
ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    DJANGO_SETTINGS_MODULE=bakerydemo.settings.production \
    PORT=8000 \
    WEB_CONCURRENCY=3 \
    HOME=/app \
    GUNICORN_CMD_ARGS="-c gunicorn-conf.py --max-requests 1200 --access-logfile - --timeout 25"

# Port exposed by this container. Should default to the port used by your WSGI
# server (Gunicorn). This is read by Dokku only. Heroku will ignore this.
EXPOSE 8000

# Copy application code.
COPY --chown=bakerydemo . .
COPY --chown=bakerydemo --from=frontend /wagtail ./wagtail

# Install your app's Python requirements.
RUN pip install -r requirements/production.txt

# Collect static. This command will move static files from application
# directories and "static_compiled" folder to the main static directory that
# will be served by the WSGI server.
RUN SECRET_KEY=none django-admin collectstatic --noinput --clear

# Don't use the root user as it's an anti-pattern and Heroku does not run
# containers as root either.
# https://devcenter.heroku.com/articles/container-registry-and-runtime#dockerfile-commands-and-runtime
USER bakerydemo

# Copy SSH private key to file, if set
# This is used for talking to GitHub over an SSH connection
ARG SSH_PRIVATE_KEY
RUN echo $SSH_PRIVATE_KEY | base64 --decode > $HOME/id_rsa
RUN ssh -oStrictHostKeyChecking=no github.com

# Run the WSGI server. It reads GUNICORN_CMD_ARGS, PORT and WEB_CONCURRENCY
# environment variable hence we don't specify a lot options below.
CMD gunicorn bakerydemo.wsgi:application
