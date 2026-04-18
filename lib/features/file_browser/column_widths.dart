/// Shared default widths for file-browser-style column tables.
///
/// Both [FilePane] (the SFTP/local file tab) and [TransferPanel]
/// (the transfer-queue panel) render tabular rows with a Size column
/// and a Modified / Time column. Users resize the SFTP columns via
/// drag handles in one view and then the other view looks off when
/// the defaults disagree, so the two surfaces share their defaults
/// via these constants.
///
/// Columns that only exist in one of the two tables (Name / Local /
/// Remote / Mode / Owner) stay local to that view — a shared constant
/// here would be noise.
class FileBrowserColumns {
  FileBrowserColumns._();

  /// Default width of the Size column.
  ///
  /// Fits strings like "999 MB" with a little breathing room. Used as
  /// the initial value in [FilePane] and
  /// [TransferPanelController]; both views let the user resize it
  /// within their own min/max clamp.
  static const double size = 55;

  /// Default width of the Modified / Time column.
  ///
  /// Fits a short locale date like "18 Apr 03:42"; both views clamp
  /// further resizes within their own min/max bounds.
  static const double modifiedOrTime = 105;
}
