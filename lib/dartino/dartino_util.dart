
/// Return `true` if the specified packages file content
/// contains references to Dartino packages.
bool containsDartinoReferences(String content, String sdkPath) {
  if (content == null || sdkPath == null) return false;
  if (content.isEmpty || sdkPath.isEmpty) return false;
  String path = new Uri.file(sdkPath).toString();
  if (!path.startsWith('file://')) return false;
  for (String line in content.split('\n')) {
    if (line.contains(path)) return true;
  }
  return false;
}
