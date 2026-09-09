// 프로필 확인/설정: 닉네임 확인·변경, 로그아웃.
// 닉네임 변경은 카카오 재인증(토큰) 후 서버에서 확정 — 타인 도용 방지.

import SwiftUI

struct ProfileView: View {
    var onClose: () -> Void

    private enum Check: Equatable { case idle, checking, ok(String), bad(String) }

    @State private var account = AccountManager.shared
    @State private var editing = false
    @State private var newNick = ""
    @State private var check: Check = .idle
    @State private var checkTask: Task<Void, Never>?
    @State private var busy = false
    @State private var error = ""
    @State private var stats: AccountManager.Stats?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("프로필").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)

                // 닉네임 표시
                VStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 52)).foregroundStyle(Theme.textDim)
                    Text(account.nickname ?? "-")
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    Text("카카오 계정 연동됨").font(.system(size: 12)).foregroundStyle(Theme.textDim)
                }
                .padding(.vertical, 4)

                if !editing { statsRow }
                if editing { nicknameEditor } else { actions }

                if !error.isEmpty {
                    Text(error).font(.system(size: 13)).foregroundStyle(.orange)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
            .frame(maxWidth: 460)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.stroke, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textDim).frame(width: 30, height: 30)
                        .background(Theme.surfaceHi, in: Circle())
                }
                .padding(10)
            }
            .padding()
        }
        .task { stats = await account.fetchStats() }   // 전적 로드
    }

    // 일반전 전적 — 승/패/승률.
    private var statsRow: some View {
        VStack(spacing: 6) {
            Text("일반전 전적\(stats.map { " · \($0.games)전" } ?? "")")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
            HStack(spacing: 10) {
                statBox("승", stats.map { "\($0.wins)" } ?? "-", .green)
                statBox("패", stats.map { "\($0.losses)" } ?? "-", .orange)
                statBox("승률", stats.map { "\(Int($0.winRate.rounded()))%" } ?? "-", .cyan)
            }
        }
    }
    private func statBox(_ label: String, _ value: String, _ color: SwiftUI.Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .heavy)).foregroundStyle(color)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 10))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                newNick = account.nickname ?? ""; check = .idle; error = ""; editing = true
            } label: {
                Text("닉네임 변경").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 46)
                    .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 12))
            }
            Button {
                account.logout(); onClose()
            } label: {
                Text("로그아웃").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange).frame(maxWidth: .infinity).frame(height: 46)
                    .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var nicknameEditor: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("새 닉네임", text: $newNick)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 1.5))
                    .onChange(of: newNick) { _, v in scheduleCheck(v) }
                Button { newNick = AccountManager.randomNickname() } label: {
                    Image(systemName: "dice.fill").font(.system(size: 17))
                        .foregroundStyle(.white).frame(width: 46, height: 46)
                        .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            statusLine
            HStack(spacing: 10) {
                Button { editing = false; error = "" } label: {
                    Text("취소").foregroundStyle(Theme.textDim).frame(maxWidth: .infinity).frame(height: 46)
                        .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 12))
                }
                Button(action: doRename) {
                    HStack(spacing: 6) {
                        if busy { ProgressView().tint(.white) }
                        Text("저장").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 46)
                    .background(canSave ? SwiftUI.Color("AccentColor") : Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSave)
            }
        }
        .onAppear { scheduleCheck(newNick) }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            switch check {
            case .idle: SwiftUI.Color.clear.frame(height: 18)
            case .checking:
                ProgressView().scaleEffect(0.7); Text("확인 중…").font(.system(size: 13)).foregroundStyle(Theme.textDim)
            case let .ok(msg):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(msg).font(.system(size: 13)).foregroundStyle(.green)
            case let .bad(msg):
                Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
                Text(msg).font(.system(size: 13)).foregroundStyle(.orange)
            }
            Spacer()
        }
        .frame(height: 18)
    }

    private var borderColor: SwiftUI.Color {
        switch check { case .ok: return .green; case .bad: return .orange; default: return Theme.stroke }
    }
    private var canSave: Bool {
        if busy { return false }
        if newNick.trimmingCharacters(in: .whitespaces) == account.nickname { return false }   // 동일하면 비활성
        if case .ok = check { return true }; return false
    }

    private func scheduleCheck(_ name: String) {
        checkTask?.cancel()
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { check = .idle; return }
        if trimmed == account.nickname { check = .ok("현재 닉네임"); return }
        check = .checking
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let r = await AccountManager.shared.checkNickname(trimmed)
            if Task.isCancelled || trimmed != newNick.trimmingCharacters(in: .whitespaces) { return }
            check = r.available ? .ok(r.reason) : .bad(r.reason)
        }
    }

    private func doRename() {
        error = ""; busy = true
        let nick = newNick.trimmingCharacters(in: .whitespaces)
        Task {
            defer { busy = false }
            do {
                let token = try await KakaoAuth.provider.login()   // 본인 확인(카카오 재인증)
                switch await account.rename(accessToken: token, nickname: nick) {
                case .success: editing = false
                case let .failure(m): error = m; check = .bad(m)
                }
            } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "변경 실패" }
        }
    }
}
