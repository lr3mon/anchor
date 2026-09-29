class Anchor < Formula
  desc "결정 기록 + 회고 CLI"
  homepage "https://github.com/lr3mon/anchor"
  url "https://github.com/lr3mon/anchor/releases/download/v0.1.0/anchor-macos-arm64.tar.gz"
  version "0.1.0"
  license "MIT"
  sha256 "1d9f0ee911609f7a9de22b1632469fea4b24df551414b1f2ceb648198b6530cc"

  depends_on :macos

  def install
    bin.install "anchor"
  end

  test do
    # --help 가 정상 출력되는지
    assert_match "anchor", shell_output("#{bin}/anchor --help")
    # 임시 DB 로 실제 기록이 되는지 (설치가 제대로 됐는지)
    db = testpath/"t.db"
    system bin/"anchor", "--db", db, "new", "brew test", "--tags", "ci"
    assert_match "brew test", shell_output("#{bin}/anchor --db #{db} ls")
  end
end
