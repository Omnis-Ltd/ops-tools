from pathlib import PurePosixPath

def normalize_relpath(p: str) -> str:
    """
    Normalize a relative path so that:
    - '\' and '/' are treated the same
    - trailing slashes are removed
    - redundant separators are collapsed
    - result always uses '/'
    """
    if not p:
        return ""
    p = p.strip().replace("\\", "/")
    return str(PurePosixPath(p))
