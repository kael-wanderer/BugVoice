#!/usr/bin/env python3
"""Generate synthetic bench clips with macOS `say` and ffmpeg.

Writes bench/clips/<name>.wav (16 kHz mono) and <name>.txt (reference).
Synthetic speech is for timing; its WER is optimistic. Owner-recorded clips
are better evidence. Usage: Scripts/make-synthetic-clips.py
"""
import pathlib, subprocess, tempfile

EN, VI = "Ava (Premium)", "Linh"
CLIPS = {
 "en-2": (EN, ['Please rename the build script.', 'Keep the old one for now.']),
 "en-3": (EN, ['The meeting moved to Thursday at three.', 'Tell the team before lunch.']),
 "en-4": (EN, ['Open the settings file and check the default language.', 'If it says English, change it to automatic.', 'Then run the tests again and send me the results.', 'After that, update the changelog with one short line.', 'Do not touch the release notes yet.']),
 "en-5": (EN, ['I reviewed the pull request this morning.', 'The chunker looks good, but the gate needs a tolerance.', 'Can you add two tests for the limits and push a fix today?', 'Also check that the report has no transcript text.', 'Thanks, and let me know when it is done.']),
 "en-6": (EN, ['Look at Sources slash VoiceCore slash DictationPipeline dot swift.', 'The run function transcribes the whole clip after release.', 'I want a new type called IncrementalSession that conforms to the Transcriber protocol.', 'It should take sample snapshots while the key is held.', 'Each finished part goes to the main model in the background.', 'On release, wait for the running pass and transcribe only the tail.', 'Do not change the cleanup step or the fidelity check.', 'Write the tests first and keep every commit small.']),
 "en-7": (EN, ['Here is the plan for next week.', 'On Monday we finish the update check and test it on the second display.', 'On Tuesday we record the benchmark clips in English, Vietnamese, and mixed speech.', 'Wednesday is for reading the report and deciding on the gate.', 'If the numbers are good, we write the phase two plan on Thursday.', 'If not, we drop the idea and write down why.', 'Friday stays free for bugs from the device checks.', 'Please keep the notes short and put them in the log.']),
 "vi-2": (VI, ['Mai mình họp lúc chín giờ.', 'Nhớ mang theo máy tính.']),
 "vi-3": (VI, ['Hôm nay trời mưa to quá.', 'Em về nhà sớm nhé.']),
 "vi-4": (VI, ['Sáng nay mình đã đọc lại bản kế hoạch.', 'Phần đầu ổn rồi, nhưng phần cuối còn thiếu số liệu.', 'Chiều nay em bổ sung giúp anh nhé.', 'Nhớ ghi rõ nguồn của từng con số.', 'Xong thì gửi lại cho anh qua email.']),
 "vi-5": (VI, ['Tuần sau công ty có buổi họp toàn thể.', 'Mọi người chuẩn bị báo cáo ngắn về công việc của mình.', 'Ai chưa xong thì báo trước cho trưởng nhóm.', 'Buổi họp sẽ bắt đầu lúc hai giờ chiều.', 'Mọi người nhớ đến đúng giờ nhé.']),
 "vi-6": (VI, ['Hôm qua mình đi chợ với mẹ từ sáng sớm.', 'Chợ đông lắm, ai cũng mua đồ chuẩn bị cho cuối tuần.', 'Mẹ mua cá, rau và một ít trái cây.', 'Trên đường về, hai mẹ con ghé quán phở quen.', 'Quán vẫn như xưa, nước dùng thơm và nóng.', 'Ăn xong, mình chở mẹ về nhà rồi đi làm.', 'Buổi chiều công việc khá bận nhưng mọi thứ đều ổn.', 'Tối nay mình sẽ gọi điện cho em gái.', 'Cuối tuần này cả nhà sẽ về quê thăm ông bà.', 'Mình đã mua vé xe từ hôm qua rồi.']),
 "vi-7": (VI, ['Mình muốn ghi lại vài ý cho dự án mới.', 'Thứ nhất, ứng dụng phải chạy hoàn toàn trên máy.', 'Thứ hai, giọng nói tiếng Việt phải được nhận dạng chính xác.', 'Thứ ba, văn bản sau khi chỉnh sửa không được làm sai số liệu.', 'Mình sẽ thử nghiệm trong hai tuần trước khi quyết định.', 'Nếu kết quả tốt, mình sẽ dùng nó mỗi ngày.', 'Nếu không, mình sẽ tìm cách khác.', 'Cuối tháng mình sẽ viết báo cáo tổng kết.', 'Mình hy vọng mọi thứ sẽ suôn sẻ.', 'Cảm ơn mọi người đã đọc.']),
 "mix-3": (VI, ['Em check lại cái API giúp anh nhé.', 'Nó đang trả về lỗi timeout.']),
 "mix-4": (VI, ['Chiều nay mình deploy bản build mới.', 'Nhớ update file config.']),
 "mix-5": (VI, ['Team mobile báo là màn hình login bị lỗi trên iPhone nhỏ.', 'Em mở Xcode và chạy simulator thử nhé.', 'Nếu thấy bug thì tạo ticket trên Jira.', 'Ghi rõ version của iOS và model máy.', 'Xong thì assign cho anh.']),
 "mix-6": (VI, ['Mình vừa review cái pull request của em.', 'Code ổn nhưng thiếu unit test cho phần cache.', 'Em thêm test rồi push lại trước khi merge nhé.', 'Nhớ chạy lại CI trên branch của em.', 'Nếu pipeline xanh thì anh approve luôn.']),
 "mix-7": (VI, ['Anh muốn refactor lại module dictation pipeline.', 'Hiện tại hàm run đang transcribe toàn bộ clip sau khi release.', 'Mình sẽ tách audio theo các khoảng pause.', 'Mỗi part sẽ được gửi vào model chính ở background.', 'Khi user nhả phím, chỉ còn phần tail cần xử lý.', 'Em viết benchmark trước, đo latency và word error rate.', 'Nếu kết quả không đạt gate thì mình bỏ feature này.', 'Nhớ commit nhỏ và chạy swift test trước mỗi lần commit.']),
 "mix-8": (VI, ['Sáng nay mình họp với team backend về database.', 'Họ muốn migrate từ Postgres sang một cluster mới.', 'Mình lo nhất là downtime và việc backup dữ liệu.', 'Em viết giúp anh một script để export toàn bộ bảng users.', 'Sau đó test restore trên môi trường staging.', 'Nếu mọi thứ ổn, tuần sau mình chạy trên production.', 'Nhớ log lại thời gian của từng bước.', 'Có vấn đề gì thì nhắn anh trên Slack nhé.']),
}

out = pathlib.Path(__file__).resolve().parent.parent / "bench" / "clips"
with tempfile.TemporaryDirectory() as tmp:
    for name, (voice, sentences) in CLIPS.items():
        aiff = pathlib.Path(tmp) / f"{name}.aiff"
        subprocess.run(["say", "-v", voice, "-o", str(aiff), " [[slnc 500]] ".join(sentences)], check=True)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(aiff), "-ac", "1", "-ar", "16000",
                        "-c:a", "pcm_s16le", str(out / f"{name}.wav")], check=True)
        (out / f"{name}.txt").write_text(" ".join(sentences) + "\n")
        print(name)
