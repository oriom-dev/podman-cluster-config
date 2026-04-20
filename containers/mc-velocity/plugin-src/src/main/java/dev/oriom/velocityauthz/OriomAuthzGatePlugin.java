package dev.oriom.velocityauthz;

import com.google.inject.Inject;
import com.velocitypowered.api.event.EventTask;
import com.velocitypowered.api.event.ResultedEvent;
import com.velocitypowered.api.event.Subscribe;
import com.velocitypowered.api.event.connection.LoginEvent;
import com.velocitypowered.api.plugin.Plugin;
import com.velocitypowered.api.proxy.Player;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import net.kyori.adventure.text.Component;
import org.slf4j.Logger;

@Plugin(
    id = "oriom-authz-gate",
    name = "Oriom Authz Gate",
    version = "0.1.0",
    description = "Checks player access against mc-whitelist-auth before joining")
public final class OriomAuthzGatePlugin {

  private static final Pattern ALLOWED_PATTERN = Pattern.compile("\\\"allowed\\\"\\s*:\\s*(true|false)");
  private static final Pattern REASON_PATTERN = Pattern.compile("\\\"reason\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"");
  private static final Pattern CHALLENGE_URL_PATTERN = Pattern.compile("\\\"url\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"");
  private static final Pattern CHALLENGE_CODE_PATTERN = Pattern.compile("\\\"code\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"");

  private final Logger logger;
  private final HttpClient httpClient;
  private final URI authorizeUri;
  private final URI challengeUri;
  private final String token;
  private final String defaultHost;
  private final boolean failOpen;
  private final Duration timeout;
  private final String denyMessage;
  private final String denyMessagePrefix;

  @Inject
  public OriomAuthzGatePlugin(Logger logger) {
    this.logger = logger;
    this.token = readRequiredEnv("AUTHZ_API_TOKEN");
    this.authorizeUri = URI.create(readEnv("AUTHZ_API_URL", "http://mc-whitelist-auth:8787/api/v1/authorize"));
    this.challengeUri = URI.create(readEnv("AUTHZ_CHALLENGE_URL", "http://mc-whitelist-auth:8787/api/v1/challenge"));
    this.defaultHost = normalizeHost(readEnv("AUTHZ_DEFAULT_HOST", "mc.oriom.dev"));
    this.failOpen = Boolean.parseBoolean(readEnv("AUTHZ_FAIL_OPEN", "false"));
    this.timeout = Duration.ofMillis(readLongEnv("AUTHZ_TIMEOUT_MS", 2500L, 100L, 30000L));
    this.denyMessage = readEnv("AUTHZ_DENY_MESSAGE", "You are not authorized for this host.");
    this.denyMessagePrefix = readEnv("AUTHZ_DENY_MESSAGE_PREFIX", "Open this URL to verify access:");
    this.httpClient = HttpClient.newBuilder().connectTimeout(this.timeout).build();

    logger.info(
        "Loaded Oriom Authz Gate plugin. authorizeEndpoint={}, challengeEndpoint={}",
        this.authorizeUri,
        this.challengeUri);
  }

  @Subscribe(priority = 100)
  public EventTask onLogin(LoginEvent event) {
    return EventTask.async(() -> enforceAuthorization(event));
  }

  private void enforceAuthorization(LoginEvent event) {
    Player player = event.getPlayer();
    String host = resolveHost(player);
    UUID uuid = player.getUniqueId();

    AuthorizationResult result;
    try {
      result = queryAuthorization(uuid, host);
    } catch (Exception error) {
      if (this.failOpen) {
        logger.warn(
            "Authz API error for player={} host={} (fail-open enabled): {}",
            player.getUsername(),
            host,
            error.getMessage());
        return;
      }

      logger.error(
          "Authz API error for player={} host={} (denying by policy)",
          player.getUsername(),
          host,
          error);
      event.setResult(ResultedEvent.ComponentResult.denied(Component.text(this.denyMessage)));
      return;
    }

    if (result.allowed()) {
      return;
    }

    logger.info(
        "Denied player={} uuid={} host={} reason={}",
        player.getUsername(),
        uuid,
        host,
        result.reason());

    String denyText = this.denyMessage;
    try {
      AccessChallenge challenge = issueAccessChallenge(uuid, host, player.getUsername());
      denyText = this.denyMessagePrefix + " " + challenge.url();
      logger.info(
          "Issued access challenge for player={} host={} code={}",
          player.getUsername(),
          host,
          challenge.code());
    } catch (Exception challengeError) {
      logger.warn(
          "Failed to issue access challenge for player={} host={}: {}",
          player.getUsername(),
          host,
          challengeError.getMessage());
    }

    event.setResult(ResultedEvent.ComponentResult.denied(Component.text(denyText)));
  }

  private AuthorizationResult queryAuthorization(UUID uuid, String host) throws Exception {
    URI requestUri = buildRequestUri(uuid, host);
    HttpRequest request =
        HttpRequest.newBuilder(requestUri)
            .timeout(this.timeout)
            .header("x-api-token", this.token)
            .GET()
            .build();

    HttpResponse<String> response = this.httpClient.send(request, HttpResponse.BodyHandlers.ofString());

    if (response.statusCode() != 200) {
      throw new IllegalStateException(
          "Unexpected authz status code: " + response.statusCode() + " body=" + response.body());
    }

    return parseAuthorizationBody(response.body());
  }

  private URI buildRequestUri(UUID uuid, String host) {
    String separator = this.authorizeUri.toString().contains("?") ? "&" : "?";
    String query =
        "uuid="
            + encode(uuid.toString())
            + "&host="
            + encode(host);

    return URI.create(this.authorizeUri + separator + query);
  }

  private AccessChallenge issueAccessChallenge(UUID uuid, String host, String username) throws Exception {
    URI requestUri = buildChallengeRequestUri(uuid, host, username);
    HttpRequest request =
        HttpRequest.newBuilder(requestUri)
            .timeout(this.timeout)
            .header("x-api-token", this.token)
            .GET()
            .build();

    HttpResponse<String> response = this.httpClient.send(request, HttpResponse.BodyHandlers.ofString());

    if (response.statusCode() != 200) {
      throw new IllegalStateException(
          "Unexpected challenge status code: " + response.statusCode() + " body=" + response.body());
    }

    return parseChallengeBody(response.body());
  }

  private URI buildChallengeRequestUri(UUID uuid, String host, String username) {
    String separator = this.challengeUri.toString().contains("?") ? "&" : "?";
    String query =
        "uuid="
            + encode(uuid.toString())
            + "&host="
            + encode(host)
            + "&username="
            + encode(username);

    return URI.create(this.challengeUri + separator + query);
  }

  private AccessChallenge parseChallengeBody(String body) {
    Matcher urlMatcher = CHALLENGE_URL_PATTERN.matcher(body);
    if (!urlMatcher.find()) {
      throw new IllegalStateException("Challenge response missing url field: " + body);
    }

    Matcher codeMatcher = CHALLENGE_CODE_PATTERN.matcher(body);
    String code = codeMatcher.find() ? codeMatcher.group(1) : "unknown";
    return new AccessChallenge(code, urlMatcher.group(1));
  }

  private AuthorizationResult parseAuthorizationBody(String body) {
    Matcher allowedMatcher = ALLOWED_PATTERN.matcher(body);
    if (!allowedMatcher.find()) {
      throw new IllegalStateException("Authz response missing allowed field: " + body);
    }

    boolean allowed = Boolean.parseBoolean(allowedMatcher.group(1));
    Matcher reasonMatcher = REASON_PATTERN.matcher(body);
    String reason = reasonMatcher.find() ? reasonMatcher.group(1) : "unknown";
    return new AuthorizationResult(allowed, reason);
  }

  private String resolveHost(Player player) {
    Optional<InetSocketAddress> virtualHost = player.getVirtualHost();
    if (virtualHost.isPresent()) {
      return normalizeHost(virtualHost.get().getHostString());
    }

    return this.defaultHost;
  }

  private static String encode(String value) {
    return URLEncoder.encode(value, StandardCharsets.UTF_8);
  }

  private static String readRequiredEnv(String key) {
    String value = System.getenv(key);
    if (value == null || value.trim().isEmpty()) {
      throw new IllegalStateException("Environment variable " + key + " is required.");
    }

    return value.trim();
  }

  private static String readEnv(String key, String defaultValue) {
    String value = System.getenv(key);
    if (value == null) {
      return defaultValue;
    }

    String trimmed = value.trim();
    return trimmed.isEmpty() ? defaultValue : trimmed;
  }

  private static long readLongEnv(String key, long defaultValue, long minValue, long maxValue) {
    String rawValue = System.getenv(key);
    if (rawValue == null || rawValue.trim().isEmpty()) {
      return defaultValue;
    }

    long parsed;
    try {
      parsed = Long.parseLong(rawValue.trim());
    } catch (NumberFormatException error) {
      return defaultValue;
    }

    if (parsed < minValue || parsed > maxValue) {
      return defaultValue;
    }

    return parsed;
  }

  private static String normalizeHost(String value) {
    String normalized = value.trim().toLowerCase();
    if (normalized.endsWith(".")) {
      normalized = normalized.substring(0, normalized.length() - 1);
    }

    if (normalized.isEmpty()) {
      return "unknown.invalid";
    }

    return normalized;
  }

  private record AuthorizationResult(boolean allowed, String reason) {}

  private record AccessChallenge(String code, String url) {}
}
