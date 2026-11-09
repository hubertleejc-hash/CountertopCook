import Foundation
import Testing
@testable import CookCore

private func close(_ value: Double?, _ expected: Double, accuracy: Double = 0.01) -> Bool {
    guard let value else { return false }
    return abs(value - expected) <= accuracy
}

@Suite struct FractionTests {
    @Test func parsing() {
        #expect(Fraction(parsing: "2") == Fraction(2))
        #expect(Fraction(parsing: "1/2") == Fraction(1, 2))
        #expect(Fraction(parsing: "1 1/2") == Fraction(3, 2))
        #expect(Fraction(parsing: "1½") == Fraction(3, 2))
        #expect(Fraction(parsing: " ¾ ") == Fraction(3, 4))
        #expect(Fraction(parsing: "0.75") == Fraction(3, 4))
        #expect(Fraction(parsing: "0,5") == Fraction(1, 2))
        #expect(Fraction(parsing: "pinch") == nil)
        #expect(Fraction(parsing: "") == nil)
        #expect(Fraction(parsing: "1/0") == nil)
    }

    @Test func display() {
        #expect(Fraction(9, 4).displayString == "2 1/4")
        #expect(Fraction(300).displayString == "300")
        #expect(Fraction(2, 3).displayString == "2/3")
        #expect(Fraction(1, 5).displayString == "1/4")      // rounded to nearest eighth
        #expect(Fraction(100, 3).displayString == "33 1/3")
        #expect(Fraction(101, 7).displayString == "14")
    }

    @Test func servingScalingFromSpec() {
        #expect(Scaler.scale("200", from: 2, to: 3) == "300")
        #expect(Scaler.scale("1 1/2", from: 2, to: 3) == "2 1/4")
        #expect(Scaler.scale("1/2", from: 2, to: 4) == "1")
        #expect(Scaler.scale("3", from: 4, to: 2) == "1 1/2")
        #expect(Scaler.scale("pinch", from: 2, to: 3) == "pinch")
        #expect(Scaler.scale("", from: 2, to: 3) == "")
    }
}

@Suite struct ConverterTests {
    @Test func volume() {
        #expect(close(Converter.convert(text: "1 1/2", from: .cup, to: .milliliter), 354.882))
        #expect(close(Converter.convert(1, from: .tablespoon, to: .teaspoon), 3))
    }

    @Test func weight() {
        #expect(close(Converter.convert(1, from: .pound, to: .gram), 453.592))
        #expect(close(Converter.convert(text: "1/2", from: .kilogram, to: .gram), 500))
    }

    @Test func temperature() {
        #expect(close(Converter.convert(180, from: .celsius, to: .fahrenheit), 356))
        #expect(close(Converter.convert(text: "350", from: .fahrenheit, to: .celsius), 176.667))
        #expect(close(Converter.convert(text: "-40", from: .celsius, to: .fahrenheit), -40))
    }

    @Test func mismatchedCategory() {
        #expect(Converter.convert(1, from: .cup, to: .gram) == nil)
    }

    @Test func format() {
        #expect(Converter.format(2.5) == "2.5")
        #expect(Converter.format(350.0) == "350")
        #expect(Converter.format(236.588) == "236.59")
    }
}

@Suite struct CookTimerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func countsDown() {
        let timer = CookTimer(name: "Sear", duration: 300, start: t0)
        #expect(timer.remaining(at: t0.addingTimeInterval(60)) == 240)
        #expect(!timer.isFinished(at: t0.addingTimeInterval(299)))
        #expect(timer.isFinished(at: t0.addingTimeInterval(300)))
    }

    @Test func twoTimersRunIndependently() {
        let a = CookTimer(name: "A", duration: 300, start: t0)
        let b = CookTimer(name: "B", duration: 600, start: t0.addingTimeInterval(10))
        let later = t0.addingTimeInterval(100)
        #expect(a.remaining(at: later) == 200)
        #expect(b.remaining(at: later) == 510)
    }

    @Test func pauseResume() {
        var timer = CookTimer(name: "Rest", duration: 300, start: t0)
        timer.pause(at: t0.addingTimeInterval(100))
        #expect(timer.isPaused)
        #expect(timer.remaining(at: t0.addingTimeInterval(1000)) == 200)
        timer.resume(at: t0.addingTimeInterval(1000))
        #expect(timer.remaining(at: t0.addingTimeInterval(1050)) == 150)
    }

    @Test func addMinute() {
        var timer = CookTimer(name: "Boil", duration: 60, start: t0)
        timer.addMinute(at: t0.addingTimeInterval(30))
        #expect(timer.remaining(at: t0.addingTimeInterval(30)) == 90)

        // +1 min on a finished timer restarts it at one minute and re-arms the alert.
        var done = CookTimer(name: "Done", duration: 10, start: t0)
        done.hasAlerted = true
        done.addMinute(at: t0.addingTimeInterval(500))
        #expect(done.remaining(at: t0.addingTimeInterval(500)) == 60)
        #expect(!done.hasAlerted)

        var paused = CookTimer(name: "P", duration: 60, start: t0)
        paused.pause(at: t0)
        paused.addMinute(at: t0)
        #expect(paused.remaining(at: t0.addingTimeInterval(999)) == 120)
    }

    @Test func countdownFormat() {
        #expect(TimeFormat.countdown(299.2) == "05:00")
        #expect(TimeFormat.countdown(59) == "00:59")
        #expect(TimeFormat.countdown(3900) == "1:05:00")
        #expect(TimeFormat.countdown(-5) == "00:00")
    }
}
