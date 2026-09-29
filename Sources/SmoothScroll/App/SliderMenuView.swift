//
// SliderMenuView.swift
// SmoothScroll
// 嵌在菜单里的「标题 + 当前值 + 滑块」一行。
//

import Cocoa

final class SliderMenuView: NSView {

    private static let preferredWidth: CGFloat = 260

    private let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let format: String
    private let onChange: (Double) -> Void

    /// - Parameter neutralValue: macOS 26+ 滑块填充从该值向两侧延伸, 直观显示与默认参数的偏离
    init(
        title: String,
        range: ClosedRange<Double>,
        value: Double,
        neutralValue: Double,
        format: String,
        onChange: @escaping (Double) -> Void
    ) {
        slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        self.format = format
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: Self.preferredWidth, height: 0))

        // macOS 26 起菜单项内边距变小、控件变高; 用 Auto Layout 撑开高度, 避免写死高度被裁切
        let horizontalInset: CGFloat
        if #available(macOS 26.0, *) {
            horizontalInset = 14
            slider.neutralValue = neutralValue
        } else {
            horizontalInset = 20
        }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .menuFont(ofSize: 0)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)

        for view in [titleLabel, valueLabel, slider] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            valueLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        refreshLabel()

        // 只在测量时固定宽度: 菜单会把条目视图拉伸到菜单宽度, 常驻的宽度约束会与之冲突
        let measuringWidth = widthAnchor.constraint(equalToConstant: Self.preferredWidth)
        measuringWidth.isActive = true
        let size = fittingSize
        measuringWidth.isActive = false
        setFrameSize(size)
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
