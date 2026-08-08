# Homebrew formula for Metis (pure Common Lisp hybrid mind).
#
# Install:
#   brew install f00-sh/tap/metis
#
# Official installer:
#   curl -fsSL https://metis.f00.sh/install.sh | bash
#
# Requires SBCL + Quicklisp for runtime (depends_on sbcl).
# SSOT for published checksums: f00-sh/homebrew-tap Formula/metis.rb

class Metis < Formula
  desc "Pure Common Lisp hybrid mind with dual-facet sealed knowledge symbols"
  homepage "https://metis.f00.sh/"
  url "https://github.com/f00-sh/metis/releases/download/4.5.0/metis-4.5.0-src.tar.gz"
  sha256 "d0cc8cea8260472cb0519ddfaaf0ab3476cea287b7c64baf891fcffdec1774e6"
  license "MIT"
  version "4.5.0"

  depends_on "sbcl"

  def install
    libexec.install Dir["*"]
    (bin/"metis").write <<~EOS
      #!/bin/bash
      set -euo pipefail
      export METIS_ROOT="#{libexec}"
      export CL_SOURCE_REGISTRY="${METIS_ROOT}/:${CL_SOURCE_REGISTRY:-}"
      exec "${METIS_ROOT}/bin/metis" "$@"
    EOS
    chmod 0755, bin/"metis"
    man1.install "man/metis.1" if File.exist?("man/metis.1")
  end

  def caveats
    <<~EOS
      Metis is a Common Lisp product (source tree + launcher), not a static binary.
      Ensure Quicklisp is installed for the SBCL user, then:

        metis version
        metis            # TUI
        metis symbol help

      Optional: link into Quicklisp local-projects:
        ln -sfn #{libexec} ~/quicklisp/local-projects/metis

      Curl installer:  curl -fsSL https://metis.f00.sh/install.sh | bash
      Docs:            https://metis.f00.sh/
    EOS
  end

  test do
    assert_match(/Metis\s+4\.5\.0/, shell_output("#{bin}/metis version"))
  end
end
