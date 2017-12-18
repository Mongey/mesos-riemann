FROM ruby:2.4

WORKDIR /tmp
COPY Gemfile Gemfile
COPY Gemfile.lock Gemfile.lock
RUN bundle install

WORKDIR /app
COPY monitor.rb .
CMD ["/app/monitor.rb"]
