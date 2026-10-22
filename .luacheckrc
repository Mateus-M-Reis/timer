std = "lua51"
max_line_length = 140
exclude_files = {
  "dev",
}

globals = {
  "lovr",
}

files["spec/*.lua"] = {
  globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "setup",
    "teardown",
  },
}
