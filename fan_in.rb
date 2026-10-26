# frozen_string_literal: true

module FanIn
  # Елемент вихідного потоку: або значення, або помилка одного з входів.
  Result = Struct.new(:ok, :value, :error) do
    def self.ok(value)
      new(true, value, nil)
    end

    def self.err(error)
      new(false, nil, error)
    end

    def ok?
      ok
    end
  end

  # Зливає кілька вхідних потоків (будь-які Enumerable) в один потік Result.
  # Кожен вхід читається в окремому потоці, тому повільний вхід не блокує решту.
  # Порядок зберігається в межах кожного входу, між входами він не гарантується.
  # Помилка входу передається як Result.err і завершує лише цей вхід.
  # Вихідний потік закривається, коли завершились усі входи.
  def self.fan_in(inputs)
    Enumerator.new do |out|
      queue = Queue.new
      workers = inputs.map { |input| start_reader(input, queue) }
      remaining = workers.size

      begin
        while remaining.positive?
          kind, payload = queue.pop
          case kind
          when :item then out << Result.ok(payload)
          when :error then out << Result.err(payload)
          when :done then remaining -= 1
          end
        end
      ensure
        workers.each(&:kill)
      end
    end
  end

  def self.start_reader(input, queue)
    Thread.new do
      Thread.current.report_on_exception = false
      begin
        input.each { |item| queue << [:item, item] }
      rescue StandardError => e
        queue << [:error, e]
      ensure
        queue << [:done, nil]
      end
    end
  end
  private_class_method :start_reader
end
