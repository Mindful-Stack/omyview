import QtQuick
import QtTest

TestCase {
    name: "Smoke"
    function test_runner_reports_pass() { compare(1 + 1, 2, "arithmetic") }
}
