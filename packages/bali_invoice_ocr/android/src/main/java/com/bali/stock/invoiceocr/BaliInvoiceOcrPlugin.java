package com.bali.stock.invoiceocr;

import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import com.googlecode.tesseract.android.TessBaseAPI;

import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class BaliInvoiceOcrPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "bali_invoice_ocr");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        executor.shutdownNow();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!"recognizeImage".equals(call.method)) {
            result.notImplemented();
            return;
        }

        final String imagePath = call.argument("imagePath");
        final String tessDataRoot = call.argument("tessDataRoot");
        String requestedLanguage = call.argument("language");
        final String language = requestedLanguage == null || requestedLanguage.trim().isEmpty()
                ? "rus+eng"
                : requestedLanguage.trim();

        if (imagePath == null || imagePath.isEmpty()) {
            result.error("INVALID_IMAGE", "Image path is required", null);
            return;
        }
        if (tessDataRoot == null || tessDataRoot.isEmpty()) {
            result.error("INVALID_TESSDATA", "Tesseract data root is required", null);
            return;
        }

        executor.execute(() -> {
            TessBaseAPI api = new TessBaseAPI();
            try {
                File image = new File(imagePath);
                if (!image.exists()) throw new IllegalArgumentException("Invoice image not found");
                File data = new File(tessDataRoot, "tessdata");
                if (!data.isDirectory()) throw new IllegalArgumentException("tessdata directory not found");
                if (!api.init(tessDataRoot, language)) throw new IllegalStateException("Unable to initialize Tesseract for " + language);
                api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO);
                api.setVariable("preserve_interword_spaces", "1");
                api.setImage(image);
                String text = api.getUTF8Text();
                mainHandler.post(() -> result.success(text == null ? "" : text));
            } catch (Throwable error) {
                mainHandler.post(() -> result.error("OCR_ERROR", error.getMessage() == null ? error.toString() : error.getMessage(), null));
            } finally {
                try {
                    api.recycle();
                } catch (Throwable ignored) {
                }
            }
        });
    }
}
