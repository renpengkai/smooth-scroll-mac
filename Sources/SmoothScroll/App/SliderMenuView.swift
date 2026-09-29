//
// SliderMenuView.swift
// SmoothScroll
// 嵌在菜单里的「标题 + 当前值 + 滑块」一行。
//

import Cocoa

final class SliderMenuView: NSView {

    private let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let format: String
    private let onChange: (Double) -> Void

    init(title: String, range: ClosedRange<Double>, value: Double, format: String, onChange: @escaping (Double) -> Void) {
        slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        self.format = format
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 46))

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .menuFont(ofSize: 0)
        titleLabel.frame = NSRect(x: 20, y: 24, width: 150, height: 18)
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 170, y: 24, width: 70, height: 18)
        addSubview(valueLabel)

        slider.frame = NSRect(x: 18, y: 4, width: 224, height: 20)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        addSubview(slider)

        refreshLabel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setValue(_ value: Double) {
        slider.doubleValue = value
        refreshLabel()
    }

    @objc private func sliderChanged() {
        refreshLabel()
        onChange(slider.doubleValue)
    }

    private func refreshLabel() {
        valueLabel.stringValue = String(format: format, slider.doubleValue)
    }
}
