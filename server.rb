$hostname = `hostname`.chomp rescue "<unknown>"

def say_it(*s)
  puts(*s)
  STDOUT.flush
end

say_it "Begin [#{$hostname}]"

require 'spyder'
require 'slop'

$signals = %i[SIGINT SIGTERM SIGUSR1].to_h { |k| [k, false] }
$signals.keys.each do |sig|
  Signal.trap(sig) do
    say_it "-ACK signal #{sig} [#{$hostname}]"
    $signals[sig] = true
    $status[:signaled] = true
  end
end

$status = {
  exiting: false,
  signaled: false,
}

opts = Slop.parse do |o|
  o.integer '--sleep', '-s', 'sleep time', default: 3
  o.integer '--wait-time', '-w', 'wait time after signal', default: 5
end

server = Spyder::Server.new('0.0.0.0', 8080)

server.router.add_route 'GET', '/' do |request, _|
  statuses = $status.map do |name, v|
    "<li><strong>#{name}</strong>: #{v ? 'yes' : 'no'}</li>"
  end

  statuses << "<li><strong>hostname</strong>: #{$hostname}</li>"

  statuses = statuses.join

  resp = Spyder::Response.new
  resp.add_standard_headers
  resp.set_header 'content-type', 'text/html'
  resp.body = <<~HTML

  <!DOCTYPE html>
  <html lang="en" dir="ltr">
    <head>
      <meta charset="utf-8">
      <title></title>
    </head>
    <body>

      <h1>cn-test</h1>

      <ul>
        #{statuses}
      </ul>

    </body>
  </html>

HTML

  resp
end

Thread.new { server.start }

wait_time = opts[:wait_time]
sleep_time = opts[:sleep]

loop do
  say_it "Sleeping #{sleep_time}s [#{$hostname}]"
  sleep(sleep_time)

  if $signals.values.any?
    $status[:exiting] = true
    say_it "Signal detected, waiting #{wait_time}s and exiting [#{$hostname}]"
    sleep(wait_time)
    break
  end
end

say_it "End gracefully [#{$hostname}]"
