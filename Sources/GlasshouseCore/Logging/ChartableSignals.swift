/// The fields worth plotting over time, and why.
///
/// Any numeric field can be charted — the log stores every one and the chart
/// view will draw whatever it is handed. This is the curated set the Dashboard
/// offers first, chosen for signals whose *history* says something their
/// current value does not.
///
/// A thermal state of "nominal" tells you nothing you did not know. A month of
/// barometric pressure shows you weather fronts arriving.
public enum ChartableSignals {
    public struct Featured: Sendable, Hashable {
        public let sensor: SensorID
        public let field: String
        public let unit: String?
        public let kind: ChartKind
        /// What the shape of this chart means, shown underneath it.
        public let reading: String

        public init(
            sensor: SensorID, field: String, unit: String?,
            kind: ChartKind = .line, reading: String
        ) {
            self.sensor = sensor
            self.field = field
            self.unit = unit
            self.kind = kind
            self.reading = reading
        }
    }

    /// How a series should be drawn.
    public enum ChartKind: Sendable, Hashable {
        /// Value against time. The default, and wrong for anything circular.
        case line

        /// A polar histogram — how often the value fell in each compass sector.
        ///
        /// Required rather than decorative for heading. On a line chart a turn
        /// from 359° to 1° is two degrees of movement drawn as a full-height
        /// cliff, and the average of 350° and 10° comes out as 180° — due
        /// south, the exact opposite of the truth. Circular data needs a
        /// circular chart.
        case rose
    }

    /// Ordered by how much the history adds over the current value.
    public static let featured: [Featured] = [
        Featured(
            sensor: "core_location.heading", field: "Magnetic heading", unit: "°",
            kind: .rose,
            reading: "Which way the phone has been pointing, as a share of readings per direction. A commute along one street shows as two opposing spikes."
        ),
        Featured(
            sensor: "core_motion.altimeter_relative", field: "Pressure", unit: "kPa",
            reading: "Air pressure. Falls as weather fronts arrive and as you climb — a flight of stairs is about 0.04 kPa."
        ),
        Featured(
            sensor: "device.battery", field: "Level", unit: "%",
            reading: "Charge over time. The slope is how fast you are using the phone; the flat sections are when you were not."
        ),
        Featured(
            sensor: "av.microphone", field: "Peak level", unit: "dBFS",
            reading: "How loud your surroundings are. Quiet nights and noisy days are visible without recording any audio."
        ),
        Featured(
            sensor: "bluetooth.scan", field: "Devices heard", unit: nil,
            reading: "How many Bluetooth devices are advertising nearby. A rough measure of how crowded a place is."
        ),
        Featured(
            sensor: "core_motion.pedometer", field: "Steps (24h)", unit: nil,
            reading: "Steps in the preceding day, sampled repeatedly."
        ),
        Featured(
            sensor: "core_motion.altimeter_absolute", field: "Altitude", unit: "m",
            reading: "Height above sea level. Changes with terrain, and with which floor you are on."
        ),
        Featured(
            sensor: "device.storage", field: "Free", unit: "GB",
            reading: "Free space. Drifts down as photos and apps accumulate, and jumps when something is deleted."
        ),
        Featured(
            sensor: "health.vitals", field: "Latest heart rate", unit: "bpm",
            reading: "Heart rate over time. Sleep, exertion and stress are all visible in the shape, which is what makes it the most personal series here."
        ),
        Featured(
            sensor: "core_location.position", field: "Speed", unit: "m/s",
            reading: "How fast you were moving. Walking sits near 1.4 m/s, cycling around 5, driving well above — so the plateaus say how you travelled."
        ),
        Featured(
            sensor: "av.camera", field: "Brightness", unit: "%",
            reading: "How bright the camera's view is. A stand-in for the ambient light sensor, which no third-party app is allowed to read — this is the same information reached the long way round."
        ),
        Featured(
            sensor: "device.screen_capture", field: "Brightness", unit: "%",
            reading: "Screen brightness. Tracks daylight if auto-brightness is on, and shows when the phone was being used in the dark."
        ),
        Featured(
            sensor: "core_motion.magnetometer", field: "Strength", unit: "µT",
            reading: "Total magnetic field strength. Earth's is about 50 µT; steel structures and electronics distort it, so indoors reads differently from outside."
        ),
        Featured(
            sensor: "core_motion.device_motion", field: "Your movement", unit: "g",
            reading: "Acceleration you caused, with gravity removed. Flat while the phone is still, spiky while it is carried."
        ),
        Featured(
            sensor: "photos.library", field: "Photos", unit: nil,
            reading: "How many photos are in the library. A slow ramp that steps up after events worth photographing."
        ),
        Featured(
            sensor: "device.uptime", field: "Uptime", unit: "hours",
            reading: "Time since the last restart. A sawtooth — each drop to zero is a reboot."
        ),
    ]

    /// The featured entry for a sensor, if it has one.
    public static func featured(for sensor: SensorID) -> Featured? {
        featured.first { $0.sensor == sensor }
    }

    /// Whether a sensor is one the Dashboard offers a chart for.
    public static func isFeatured(_ sensor: SensorID) -> Bool {
        featured.contains { $0.sensor == sensor }
    }
}
