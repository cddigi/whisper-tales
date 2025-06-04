#!/usr/bin/env elixir

# Test script for ChatterboxServer integration
Application.ensure_started(:httpoison)

defmodule TTSTest do
  def test_server_availability do
    IO.puts("Testing ChatterboxServer availability...")
    
    case HTTPoison.get("http://127.0.0.1:7860/") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        IO.puts("✅ TTS server is available: #{body}")
        true
      {:error, reason} ->
        IO.puts("❌ TTS server not available: #{inspect(reason)}")
        false
    end
  end
  
  def test_synthesis(text) do
    IO.puts("Testing TTS synthesis for: #{text}")
    
    payload = %{
      "data" => [text]
    }
    
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
    
    case HTTPoison.post(
      "http://127.0.0.1:7860/api/predict",
      Jason.encode!(payload),
      headers,
      recv_timeout: 30_000
    ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"data" => [audio_b64]}} ->
            case Base.decode64(audio_b64) do
              {:ok, audio_data} ->
                IO.puts("✅ TTS synthesis successful!")
                IO.puts("   Audio size: #{byte_size(audio_data)} bytes")
                
                # Save to file for testing
                filename = "midwest_sample_#{:rand.uniform(1000)}.wav"
                File.write!(filename, audio_data)
                IO.puts("   Saved to: #{filename}")
                
                {:ok, audio_data, filename}
              :error ->
                IO.puts("❌ Failed to decode base64 audio")
                {:error, :invalid_base64}
            end
          {:error, reason} ->
            IO.puts("❌ Failed to parse JSON response: #{inspect(reason)}")
            {:error, :json_parse_error}
        end
      {:ok, %HTTPoison.Response{status_code: status}} ->
        IO.puts("❌ TTS request failed with status: #{status}")
        {:error, {:http_error, status}}
      {:error, reason} ->
        IO.puts("❌ HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

# Run tests
IO.puts("=== Chatterbox TTS Integration Test ===")
IO.puts("")

# Test 1: Server availability
if TTSTest.test_server_availability() do
  IO.puts("")
  
  # Test 2: Midwest accent samples
  midwest_phrases = [
    "Oh, you betcha! That hotdish was real good, don'tcha know.",
    "Ope, just gonna squeeze right past ya there.",
    "It's colder than a well digger's belt buckle out there today.",
    "The Packers are gonna win the Super Bowl this year, mark my words."
  ]
  
  IO.puts("Generating Midwest accent samples...")
  IO.puts("")
  
  Enum.each(midwest_phrases, fn phrase ->
    case TTSTest.test_synthesis(phrase) do
      {:ok, _audio_data, filename} ->
        IO.puts("✅ Generated: #{filename}")
      {:error, reason} ->
        IO.puts("❌ Failed to generate audio for: #{phrase}")
        IO.puts("   Reason: #{inspect(reason)}")
    end
    IO.puts("")
  end)
else
  IO.puts("❌ Cannot proceed without TTS server")
  System.halt(1)
end

IO.puts("=== Test Complete ===")