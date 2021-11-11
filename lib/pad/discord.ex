defmodule Pad.Consumer do
  use Nostrum.Consumer

  import Nostrum.Struct.Embed

  alias Nostrum.Api
  alias Nostrum.Struct.Embed
  alias Nostrum.Struct.{Interaction, ApplicationCommandInteractionData}

  alias Pad.Songlist
  alias PadWeb.Router.Helpers, as: Routes

  require Logger

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def broadcast_new_pad(pad_id) do
    url =
      Routes.url(PadWeb.Endpoint)
      |> URI.merge(Routes.page_path(PadWeb.Endpoint, :index, pad_id))
      |> URI.to_string()

    embed =
      %Embed{}
      |> put_description("Pad [#{String.replace(pad_id, "_", " ")}](#{url}) was created")
      |> put_color(Application.fetch_env!(:pad, :embed_color))
      |> put_timestamp(
        DateTime.utc_now()
        |> DateTime.to_iso8601()
      )

    Api.create_message(Application.fetch_env!(:pad, :diff_channel), embeds: [embed])
  end

  def broadcast_change(diff, pad) do
    filename = "#{pad.pad_id}_#{pad.last_edited}.webp"

    System.cmd("python3", ["txt2img.py", "diff/#{filename}", diff])
    |> case do
      {_, 0} ->
        image_url =
          Routes.url(PadWeb.Endpoint)
          |> URI.merge(Routes.api_path(PadWeb.Endpoint, :diff, filename))
          |> URI.to_string()

        url =
          Routes.url(PadWeb.Endpoint)
          |> URI.merge(Routes.page_path(PadWeb.Endpoint, :index, pad.pad_id))
          |> URI.to_string()

        embed =
          %Embed{}
          |> put_description("[#{String.replace(pad.pad_id, "_", " ")}](#{url}) was updated")
          |> put_image(image_url)
          |> put_color(Application.fetch_env!(:pad, :embed_color))
          |> put_timestamp(
            pad.last_edited
            |> DateTime.from_unix!(:millisecond)
            |> DateTime.to_iso8601()
          )

        Api.create_message(Application.fetch_env!(:pad, :diff_channel), embeds: [embed])

      r ->
        IO.inspect(r)
    end
  end

  def do_interaction(
        "parts",
        %Interaction{data: %{options: [%{name: "song", value: pad_name}]}} = interaction
      ) do
    case Songlist.find_pad(pad_name) do
      [pad | _] ->
        pad = Songlist.get_pad(pad)

        embed =
          %Embed{}
          |> put_title(String.replace(pad.pad_id, "_", " "))
          |> put_url(pad.url)
          |> put_description(Enum.join(pad.needs, ", "))
          |> put_color(Application.fetch_env!(:pad, :embed_color))

        Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{
            embeds: [embed]
          }
        })

      _ ->
        Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{
            content: "Dude weed lmao cannot find shit"
          }
        })
    end
  end

  def do_interaction(
        "songpart",
        %Interaction{
          data: %{options: [%{name: "song", value: pad_name}, %{name: "part", value: part}]}
        } = interaction
      ) do
    case Songlist.find_pad(pad_name) do
      [pad | _] ->
        part = String.downcase(part)

        sheets =
          Songlist.get_pad(pad)
          |> Map.get(:instruments)
          |> Enum.filter(&(String.downcase(elem(&1, 0)) =~ part))
          |> Enum.map(&"#{elem(&1, 0)}: <#{elem(&1, 1).sheet}>")
          |> Enum.join("\n")

        Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{
            content: sheets
          }
        })

      _ ->
        Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{
            content: "Dude weed lmao cannot find shit"
          }
        })
    end
  end

  def do_interaction(
        "needs",
        %Interaction{data: %{options: [%{name: "role"}], resolved: %{roles: roles}}} = interaction
      ) do
    parts =
      roles
      |> Enum.map(&elem(&1, 1).name)

    needs(parts, interaction, "Needs #{Enum.join(parts, ", ")}")
  end

  def do_interaction(
        "needs",
        %Interaction{
          data: %{options: [%{name: "user"}], resolved: %{members: members}},
          guild_id: guild_id
        } = interaction
      ) do
    members
    |> Enum.map(&elem(&1, 1).roles)
    |> Enum.reduce([], &(&2 ++ &1))
    |> case do
      [] ->
        Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{
            content: "User has no roles!"
          }
        })

      roles ->
        case Api.get_guild_roles(guild_id) do
          {:ok, guild_roles} ->
            parts =
              guild_roles
              |> Stream.map(&{&1.id, &1.name})
              |> Stream.filter(&(elem(&1, 0) in roles))
              |> Enum.map(&elem(&1, 1))

            needs(parts, interaction, "Needs #{Enum.join(parts, ", ")}")

          _ ->
            nil
        end
    end
  end

  def do_interaction(
        "needs",
        %Interaction{data: %{options: [%{name: "part", value: part}]}} = interaction
      ) do
    needs([part], interaction, "Needs #{part}")
  end

  def do_interaction(
        "needs",
        %Interaction{
          guild_id: guild_id,
          member: %{roles: roles, user: %{username: username, discriminator: discriminator}}
        } = interaction
      ) do
    case Api.get_guild_roles(guild_id) do
      {:ok, guild_roles} ->
        guild_roles
        |> Stream.map(&{&1.id, &1.name})
        |> Stream.filter(&(elem(&1, 0) in roles))
        |> Enum.map(&elem(&1, 1))
        |> needs(interaction, "Needs #{username}##{discriminator}")

      _ ->
        nil
    end
  end

  def do_interaction(
        "songinfo",
        %Interaction{data: %{options: [%{name: "song", value: pad_name}]}} = interaction
      ) do
    case Songlist.find_pad(pad_name) do
      [pad | _] ->
        text = Songlist.get_text(pad)
        {text_end, _} = :binary.match(text, "~~~~~~~~")

        text =
          text
          |> String.slice(0..(text_end - 1))
          |> String.trim()

        filename = "#{pad}.webp"

        System.cmd("python3", ["txt2img.py", "songinfo/#{filename}", text])
        |> case do
          {_, 0} ->
            embed =
              %Embed{}
              |> put_title(String.replace(pad, "_", " "))
              |> put_url(Routes.page_url(PadWeb.Endpoint, :index, pad))
              |> put_image(Routes.api_url(PadWeb.Endpoint, :songinfo, filename))
              |> put_color(Application.fetch_env!(:pad, :embed_color))

            Api.create_interaction_response(interaction, %{
              type: 4,
              data: %{
                embeds: [embed]
              }
            })

          r ->
            IO.inspect(r)
        end

      _ ->
        Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{
            content: "Dude weed lmao cannot find shit"
          }
        })
    end
  end

  def do_interaction(
        _,
        %Interaction{
          data: %ApplicationCommandInteractionData{custom_id: "page:" <> page},
          message: %{interaction: %{id: id} = interaction2}
        } = interaction
      ) do
    Pad.Paginator.change_page(interaction, interaction2, id, page)
  end

  def do_interaction(
        _,
        %Interaction{
          data: %ApplicationCommandInteractionData{custom_id: "page_jump:" <> page},
          message: %{interaction: %{id: id} = interaction2}
        } = interaction
      ) do
    Pad.Paginator.change_page(interaction, interaction2, id, page)
  end

  def do_interaction(name, interaction) do
    Logger.warning("Unhandled interaction #{name}: #{inspect(interaction)}")

    Api.create_interaction_response(interaction, %{
      type: 1,
      data: %{content: "Unhandled interaction #{name}: #{inspect(interaction)}", flags: 64}
    })
  end

  def needs(parts, interaction, title) do
    parts
    |> Enum.map(&String.downcase(&1))
    |> Songlist.needs()
    |> Enum.sort(&(length(&1.original_needs) < length(&2.original_needs)))
    |> Stream.map(
      &"(#{length(&1.original_needs)}) [#{&1.pad_id |> String.replace("_", " ")}](#{&1.url}) `#{Enum.join(&1.needs, ", ")}`"
    )
    |> Enum.reduce([[]], fn line, [top | tail] ->
      if length(top) == 10 or String.length(Enum.join(top ++ [line], "\n")) > 5000 do
        [[line]] ++ [top | tail]
      else
        [top ++ [line] | tail]
      end
    end)
    |> Enum.reverse()
    |> case do
      [] ->
        Api.create_interaction_response(interaction, %{
          type: 4,
          data: %{
            content: "Dude weed lmao cannot find shit"
          }
        })

      pages ->
        pages
        |> Enum.with_index()
        |> Enum.map(fn {page, i} ->
          %Embed{}
          |> put_title(title)
          |> put_description(Enum.join(page, "\n"))
          |> put_footer("#{i + 1}/#{length(pages)}")
          |> put_color(Application.fetch_env!(:pad, :embed_color))
        end)
        |> Pad.Paginator.create(interaction)
    end
  end

  def handle_event({:INTERACTION_CREATE, %Interaction{data: %{name: name}} = interaction, _}) do
    do_interaction(name, interaction)
  end

  def handle_event(_event) do
    :noop
  end
end
