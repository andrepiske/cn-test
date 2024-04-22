require "oj"
require "multi_json"
require "pry-byebug"

class Pod
  attr_reader :name, :created_at, :created_line
  attr_reader :began_at
  attr_reader :signaled_at
  attr_reader :exiting_at
  attr_reader :shutdown_at
  attr_reader :last_ping
  attr_reader :state

  def initialize(name, created_at, created_line)
    @name = name
    @created_at = created_at
    @created_line = created_line
    @state = :unborn
  end

  def chr
    {
      unborn: '.',
      alive: began_at ? '*' : '/',
      signaled: 'ä',
      exiting: '<',
      shutdown: '_',
      invalid: 'i',
    }.fetch(@state)
  end

  def register_ping(time)
    # transition_state!(nil, from: %i(alive signaled exiting))
    return unless transition_state!(@state == :unborn ? :alive : @state, from: %i(unborn alive signaled exiting))
    @last_ping = time
  end

  def register_signal(time)
    return unless transition_state!(:signaled, from: %i(alive signaled exiting))
    @signaled_at = time
  end

  def register_exiting(time)
    return unless transition_state!(:exiting, from: %i(signaled))
    @exiting_at = time
  end

  def register_shutdown(time)
    return unless transition_state!(:shutdown, from: %i(exiting))
    @shutdown_at = time
  end

  def begin(time)
    return unless transition_state!(:alive, from: %i(unborn))
    @began_at = time
  end

  def transition_state!(to_state, from:)
    return false if @state == :invalid
    to_state = @state unless to_state
    if !from.include?(@state)
      @state = :invalid
      return false
      # puts "[#{@name}] Can't transition pod to #{to_state} from #{@state}"
      # exit(1)
    end
    @state = to_state

    true
  end
end

class LogChecker
  def initialize(file_name)
    @lines = []
    fp = File.open(file_name, 'r')
    fp.each_line do |line|
      @lines << line
    end
    @lines.reverse!
    @pods = {}
  end

  def process_line(pod_name, time, content, line)
    pod = @pods[pod_name]
    newly_created = !pod
    if !pod
      pod = @pods[pod_name] = Pod.new(pod_name, time, line)
    end

    if content =~ /^Sleeping/
      pod.register_ping(time)
    elsif content =~ /^Begin/
      pod.begin(time)
    elsif content =~ /^Signal detected,/
      pod.register_exiting(time)
    elsif content =~ /^-ACK signal/
      pod.register_signal(time)
    elsif content =~ /^End gracefully/
      pod.register_shutdown(time)
    else
      puts "Unrecognized line: #{content}"
      binding.pry
      exit(1)
    end
  end

  def pods_line
    @pods.values.map(&:chr).join
  end

  def print_summary
    puts "-------\nSummary:"
    [
      [:unborn, []],
      [:alive, [:last_ping]],
      [:signaled, [:signaled_at]],
      [:exiting, [:exiting_at, :last_ping]],
      [:shutdown, [:shutdown_at, :last_ping]],
      [:invalid, []],
    ].each do |state, attrs|
      pods = @pods.values.select { |x| x.state == state }
      puts "#{state.to_s.upcase}: \##{pods.length}"
      pods.each do |pod|
        ats = []
        attrs.each do |name|
          value = pod.public_send(name)
          ats << "#{name}=#{value.iso8601}"
        end
        puts " #{pod.chr} #{pod.name} #{ats.join(' ')}"
      end
    end
  end

  def run
    @lines.each do |_line|
      line = MultiJson.load(_line)
      next unless line['_tag'].include?('kubes-review')
      next unless line.dig('_label', 'app_kubernetes_io/name') == 'cntest'
      pod = line['pod']
      time = Time.at(line['_ts'] / 1000.0)

      content = line['_line']

      # puts("[#{time.rfc2822}] -> #{content}")
      puts("[#{time.rfc2822} | #{pods_line}] #{content}")
      process_line(pod, time, content, line)
    end

    print_summary
  end
end

LogChecker.new(ARGV[0]).run
