// 카카오 로그인 + 닉네임 가입 화면.
// 흐름: 카카오 로그인 → (기존회원) 완료 / (신규) 닉네임 가입 → 완료.
// 닉네임은 타이핑마다 사용가능 여부를 서버에 확인하고, 기본값은 영문5+숫자2 랜덤.

import SwiftUI

struct LoginView: View {
    var onDone: () -> Void          // 로그인/가입 완료
    var onCancel: () -> Void

    private enum Step: Equatable { case login, signup }
    private enum Check: Equatable { case idle, checking, ok(String), bad(String) }

    @State private var step: Step = .login
    @State private var token: String?               // 카카오 액세스 토큰(가입에 사용)
    @State private var busy = false
    @State private var error = ""

    // 닉네임 가입
    @State private var nick = AccountManager.randomNickname()
    @State private var check: Check = .idle
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Text(step == .login ? "룬컬렉트 시작하기" : "닉네임 만들기")
                    .font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)

                if step == .login { loginBody } else { signupBody }

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
                Button { onCancel() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textDim).frame(width: 30, height: 30)
                        .background(Theme.surfaceHi, in: Circle())
                }
                .padding(10)
            }
            .padding()
        }
    }

    // MARK: 로그인
    private var loginBody: some View {
        VStack(spacing: 14) {
            Text("일반전은 카카오 로그인이 필요해요.")
                .font(.system(size: 14)).foregroundStyle(Theme.textDim)
            Button(action: doKakaoLogin) {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.black) }
                    Image(systemName: "message.fill")
                    Text("카카오 로그인").font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(SwiftUI.Color(red: 1.0, green: 0.898, blue: 0.0), in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(busy)
        }
    }

    // MARK: 닉네임 가입
    private var signupBody: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                TextField("닉네임", text: $nick)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 1.5))
                    .onChange(of: nick) { _, v in scheduleCheck(v) }
                Button { nick = AccountManager.randomNickname() } label: {
                    Image(systemName: "dice.fill").font(.system(size: 18))
                        .foregroundStyle(.white).frame(width: 48, height: 48)
                        .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            statusLine
            Button(action: doRegister) {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    Text("가입하고 시작").font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 50)
                .background(canSubmit ? SwiftUI.Color("AccentColor") : Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSubmit)
        }
        .onAppear { scheduleCheck(nick) }   // 기본 닉네임도 즉시 확인
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
    private var canSubmit: Bool {
        if busy { return false }
        if case .ok = check { return true }; return false
    }

    // MARK: 동작
    private func doKakaoLogin() {
        error = ""; busy = true
        Task {
            defer { busy = false }
            do {
                let tk = try await KakaoAuth.provider.login()
                token = tk
                switch await AccountManager.shared.loginWithKakao(accessToken: tk) {
                case .registered: onDone()
                case .needsNickname: step = .signup
                case let .failed(m): error = m
                }
            } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "로그인 실패" }
        }
    }

    private func scheduleCheck(_ name: String) {
        checkTask?.cancel()
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { check = .idle; return }
        check = .checking
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)   // 디바운스
            if Task.isCancelled { return }
            let r = await AccountManager.shared.checkNickname(trimmed)
            if Task.isCancelled || trimmed != nick.trimmingCharacters(in: .whitespaces) { return }
            check = r.available ? .ok(r.reason) : .bad(r.reason)
        }
    }

    private func doRegister() {
        guard let tk = token else { error = "로그인이 필요해요"; return }
        error = ""; busy = true
        Task {
            defer { busy = false }
            switch await AccountManager.shared.register(accessToken: tk, nickname: nick.trimmingCharacters(in: .whitespaces)) {
            case .success: onDone()
            case let .failure(m): error = m; check = .bad(m)   // 동시 가입 등으로 막히면 다시 고르게
            }
        }
    }
}
