import 'package:http/http.dart' as http;

Future<http.StreamedResponse> sendMultipartWithProgress(
  http.Client client,
  http.MultipartRequest request, {
  void Function(int sentBytes, int totalBytes)? onProgress,
}) async {
  final body = request.finalize();
  final streamedRequest = http.StreamedRequest(request.method, request.url)
    ..headers.addAll(request.headers)
    ..contentLength = request.contentLength;
  final response = client.send(streamedRequest);
  var sentBytes = 0;
  var bodyClosed = false;
  try {
    await for (final chunk in body) {
      streamedRequest.sink.add(chunk);
      sentBytes += chunk.length;
      onProgress?.call(sentBytes, streamedRequest.contentLength ?? sentBytes);
    }
    final closing = streamedRequest.sink.close();
    bodyClosed = true;
    await closing;
    return await response;
  } on Object catch (error) {
    if (!bodyClosed) {
      streamedRequest.sink.addError(error);
      await streamedRequest.sink.close();
    }
    rethrow;
  }
}
