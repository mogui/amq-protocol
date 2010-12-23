# encoding: binary

module AMQ
  module Protocol
    class Frame
      TYPES         = {method: 1, headers: 2, body: 3, heartbeat: 4}
      TYPES_REVERSE = TYPES.inject({}) { |hash, pair| hash.merge!(pair[1] => pair[0]) }
      TYPES_OPTIONS = TYPES.keys
      CHANNEL_RANGE = (0..65535)
      FINAL_OCTET   = "\xCE" # 206

      TYPES.default_proc = lambda { |hash, key| key if (1..4).include?(key) }

      # The channel number is 0 for all frames which are global to the connection and 1-65535 for frames that refer to specific channels.
      def self.encode(type, payload, channel)
        raise FrameTypeError.new(TYPES_OPTIONS) unless TYPES_OPTIONS.include?(type) or (type = TYPES[type])
        raise RuntimeError.new("Channel has to be 0 or an integer in range 1..65535") unless CHANNEL_RANGE.include?(channel)
        raise RuntimeError.new("Payload can't be nil") if payload.nil?
        [TYPES[type], channel, payload.bytesize].pack("cnN") + payload + FINAL_OCTET
      end

      class << self
        alias_method :__new__, :new
      end

      def self.new(original_type, *args)
        type  = TYPES[original_type]
        klass = CLASSES[type]
        raise "Type must be an integer in range 1..4 or #{TYPES_OPTIONS.inspect}, was #{original_type.inspect}" if klass.nil?
        klass.new(*args)
      end

      def self.decode(readable)
        header = readable.read(7)
        raise EmptyResponseError.new if header.nil?
        type_id, channel, size = header.unpack("cnN")
        type = TYPES_REVERSE[type_id]
        data = readable.read(size + 1)
        payload, frame_end = data[0..-2], data[-1]
        raise RuntimeError.new("Frame doesn't end with #{FINAL_OCTET} as it must, which means the size is miscalculated.") unless frame_end == FINAL_OCTET
        raise FrameTypeError.new(TYPES_OPTIONS) unless TYPES_OPTIONS.include?(type)
        self.new(type, payload, channel)
      end
    end

    class FrameSubclass < Frame
      # Restore original new
      class << self
        alias_method :new, :__new__
        undef_method :decode
      end

      def self.id
        @id
      end

      def self.encode(payload, channel)
        super(@id, payload, channel)
      end

      attr_accessor :channel
      attr_reader :payload
      def initialize(payload, channel)
        @payload, @channel = payload, channel
      end

      def size
        @payload.bytesize
      end

      def encode
        [self.class.id, @channel, self.size].pack("cnN") + @payload + FINAL_OCTET
      end
    end

    class MethodFrame < FrameSubclass
      @id = 1

      def method_class
        klass_id, method_id = self.payload.unpack("n2")
        index = klass_id << 16 | method_id
        AMQ::Protocol::METHODS[index]
      end

      def decode_payload
        self.method_class.decode(@payload[4..-1])
      end
    end

    class HeadersFrame < FrameSubclass
      @id = 2
    end

    class BodyFrame < FrameSubclass
      @id = 3
    end

    class HeartbeatFrame < FrameSubclass
      @id = 4
    end

    Frame::CLASSES = {method: MethodFrame, headers: HeadersFrame, body: BodyFrame, heartbeat: HeadersFrame}
    Frame::CLASSES.default_proc = lambda { |hash, key| hash[Frame::TYPES_REVERSE[key]] if (1..4).include?(key) }
  end
end
