/// How decoded frames reach the widget tree.
///
/// The default, [auto], is the right answer for almost every app. The other two exist because
/// neither path is universally better: a texture composites like any other widget and costs
/// nothing extra, while a SurfaceView is the only path some decoders can feed correctly.
enum FVideoRenderMode {
  /// A SurfaceView on televisions, a Flutter texture everywhere else — until the video turns out
  /// to be one a texture cannot show.
  ///
  /// That is 10-bit and HDR video: AV1 as most services encode it, HEVC Main 10, Dolby Vision.
  /// Its frames reach the texture as green and magenta noise on phones too, whichever decoder
  /// produced them, so a player that meets one moves to the SurfaceView for the rest of its
  /// life. 8-bit video stays on the texture.
  auto,

  /// Always a Flutter texture — `Texture(textureId: ...)`.
  ///
  /// Frames travel through an `ImageReader` and are imported into the GPU as an external image.
  /// That import only works while the decoder writes a plain, linear 8-bit buffer, which is
  /// true of every phone decoder for H.264 and 8-bit HEVC. 10-bit video comes out as green
  /// noise on this path, and asking for it by name means it stays here regardless.
  texture,

  /// Always an Android `SurfaceView`, mounted as a platform view.
  ///
  /// The buffer goes straight to SurfaceFlinger in whatever layout the decoder produced, so this
  /// is the path that survives decoders whose output the texture import cannot read — television
  /// AV1 decoders, chiefly, which write vendor-compressed frames that the import turns into green
  /// and magenta banding.
  ///
  /// The cost is hybrid composition: every Flutter frame drawn above the video is copied through
  /// an intermediate image. Worth it on a TV, wasteful on a phone.
  surfaceView,
}
