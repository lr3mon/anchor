class Anchor < Formula
  desc "결정 기록 + 회고 CLI"
  homepage "https://github.com/lr3mon/anchor"
  url "https://github.com/lr3mon/anchor/releases/download/v#{version}/anchor-macos-arm64.tar.gz"
  version "0.1.0"
  license "MIT"
  sha256 "REPLACE_WITH_SHA256"

  def install
    bin.install "anchor"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/anchor --help")
    # 임시 DB 로 실제 기록이 되는지 확인
    system "#{bin}/anchor", "--db", "#{testpath}/t.db", "new", "brew 테스트"
    assert_match "brew 테스트", shell_output("#{bin}/anchor --db #{testpath}/t.db ls")
  end
end
