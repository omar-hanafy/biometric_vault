/// Rejects names that are not plain identifiers before storage is accessed.
void validateStorageName(String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains('\u0000') ||
      name.contains('/') ||
      name.contains(r'\')) {
    throw ArgumentError.value(
      name,
      'name',
      'Storage name must be a nonempty plain identifier without path '
          'separators or NUL characters; "." and ".." are reserved.',
    );
  }
}
