class Anchor < Formula
  desc "결정 기록 + 회고 (CLI, 메뉴바 앱)"
  homepage "https://github.com/lr3mon/anchor"
  url "https://github.com/lr3mon/anchor/releases/download/v0.3.0/anchor-macos-arm64.tar.gz"
  version "0.3.0"
  license "MIT"
  sha256 "541f389fdd3d3ab849d1700313a586759afb2fdf3f46c4d7fca8ffdc87acb3bf"

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
    # 집계 명령이 동작하는지 (v0.3.0 추가)
    assert_match "연속", shell_output("#{bin}/anchor --db #{db} stats")
  end
end
