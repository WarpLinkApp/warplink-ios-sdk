import Foundation

extension WarpLink {

    /// Names the cross-platform SDK that hosts this one, so the match request
    /// reports `react-native` or `flutter` as its `sdk_platform` instead of
    /// `ios`. Call it before `configure`.
    ///
    /// Gated by `@_spi` because it belongs to the React Native and Flutter
    /// bridges, not to an app. Any other name is ignored and the platform stays
    /// `ios`.
    @_spi(ReactNative) @_spi(Flutter)
    public static func declareHostWrapper(_ name: String) {
        TetherServices.declareWrapper(name)
    }
}
