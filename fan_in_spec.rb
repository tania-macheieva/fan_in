# frozen_string_literal: true

require 'timeout'
require_relative 'fan_in'

# Керований вхідний потік: елементи подаються вручну, потік закривається явно.
class Channel
  include Enumerable

  def initialize
    @queue = Queue.new
  end

  def push(item)
    @queue << [:value, item]
    self
  end

  def fail!(error)
    @queue << [:error, error]
  end

  def close
    @queue << [:close]
  end

  def each
    loop do
      kind, payload = @queue.pop
      break if kind == :close

      raise payload if kind == :error

      yield payload
    end
  end
end

RSpec.describe FanIn do
  def tagged(tag, count)
    Enumerator.new do |y|
      count.times do |i|
        y << [tag, i]
        sleep(rand * 0.002)
      end
    end
  end

  def values(results)
    results.map(&:value)
  end

  def order_of(tag, items)
    items.select { |t, _| t == tag }.map(&:last)
  end

  describe 'merging' do
    it 'merges two streams, keeping the order within each stream' do
      merged = values(described_class.fan_in([tagged(:a, 30), tagged(:b, 30)]).to_a)

      expect(merged.size).to eq(60)
      expect(order_of(:a, merged)).to eq((0...30).to_a)
      expect(order_of(:b, merged)).to eq((0...30).to_a)
    end

    it 'merges three streams, keeping the order within each stream' do
      merged = values(described_class.fan_in([tagged(:a, 20), tagged(:b, 20), tagged(:c, 20)]).to_a)

      expect(merged.size).to eq(60)
      %i[a b c].each { |tag| expect(order_of(tag, merged)).to eq((0...20).to_a) }
    end

    it 'does not let a slow input block the others' do
      slow = Channel.new
      fast = Channel.new
      received = Queue.new
      consumer = Thread.new { described_class.fan_in([slow, fast]).each { |r| received << r.value } }

      fast.push(:f1).push(:f2)
      expect(Timeout.timeout(2) { [received.pop, received.pop] }).to eq(%i[f1 f2])

      slow.close
      fast.close
      Timeout.timeout(2) { consumer.join }
    end
  end

  describe 'closing' do
    it 'finishes only after all inputs have finished' do
      a = Channel.new
      b = Channel.new
      consumer = Thread.new { described_class.fan_in([a, b]).to_a }

      a.push(1).close
      b.push(2)
      sleep(0.05)
      expect(consumer).to be_alive

      b.close
      expect(values(Timeout.timeout(2) { consumer.value })).to contain_exactly(1, 2)
    end

    it 'closes immediately when there are no inputs' do
      expect(Timeout.timeout(2) { described_class.fan_in([]).to_a }).to eq([])
    end

    it 'stops reading the inputs when the consumer stops early' do
      endless = Enumerator.new { |y| loop { y << 1; sleep(0.001) } }

      expect(Timeout.timeout(2) { described_class.fan_in([endless, endless]).first(3) }.size).to eq(3)
    end
  end

  describe 'errors' do
    it 'reports the error of one input without blocking the others' do
      broken = Channel.new
      healthy = Channel.new
      broken.push(:b1)
      broken.fail!(RuntimeError.new('boom'))
      healthy.push(:h1).push(:h2).push(:h3).close

      results = Timeout.timeout(2) { described_class.fan_in([broken, healthy]).to_a }
      ok, failed = results.partition(&:ok?)

      expect(values(ok).grep(/\Ah/)).to eq(%i[h1 h2 h3])
      expect(values(ok)).to include(:b1)
      expect(failed.map { |r| r.error.message }).to eq(['boom'])
    end

    it 'delivers the items before the error in the failing input order' do
      broken = Channel.new
      broken.push(:first)
      broken.fail!(RuntimeError.new('boom'))

      results = Timeout.timeout(2) { described_class.fan_in([broken]).to_a }

      expect(results.map(&:ok?)).to eq([true, false])
      expect(results.first.value).to eq(:first)
    end

    it 'closes the output when all inputs fail' do
      a = Channel.new
      b = Channel.new
      a.fail!(RuntimeError.new('a failed'))
      b.fail!(RuntimeError.new('b failed'))

      results = Timeout.timeout(2) { described_class.fan_in([a, b]).to_a }

      expect(results.map { |r| r.error.message }).to contain_exactly('a failed', 'b failed')
    end
  end
end
